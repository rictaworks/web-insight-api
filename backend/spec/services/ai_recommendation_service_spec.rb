require 'rails_helper'

RSpec.describe AiRecommendationService, type: :service do
  let(:user) { User.create!(google_sub: 'user_123', display_name: 'Alice') }
  let(:site) { Site.create!(name: 'My Site', url: 'https://example.com', user: user) }
  let(:service) { described_class.new(site) }
  let(:api_key) { 'test_api_key' }

  before do
    stub_const('ENV', ENV.to_h.merge('GEMINI_API_KEY' => api_key, 'LANGSMITH_API_KEY' => 'smith_key'))
  end

  describe '#generate_recommendations' do
    let(:llm_double) { instance_double(Langchain::LLM::GoogleGemini) }
    let(:chat_response_double) { double('response', chat_completion: response_json) }
    let(:response_json) do
      {
        recommendations: [
          {
            category: 'UX',
            priority: 1,
            description: 'ボタンの配置を改善してください',
            estimated_impact: '高'
          },
          {
            category: 'パフォーマンス',
            priority: 2,
            description: '画像のサイズを最適化してください',
            estimated_impact: '中'
          }
        ]
      }.to_json
    end

    before do
      allow(Langchain::LLM::GoogleGemini).to receive(:new).and_return(llm_double)
      allow(llm_double).to receive(:chat).and_return(chat_response_double)

      # Stub LangSmith network requests using RSpec's HTTP mocking
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(double('response', code: '200', body: '{}'))
    end

    context 'when within daily limit' do
      it 'sends the system prompt as a top-level param and messages in Gemini parts shape' do
        # Gemini's API has no 'system' message role — `system` is a separate
        # top-level parameter — and each `messages` entry must carry Gemini's
        # own `parts: [{ text: ... }]` shape rather than an OpenAI/Anthropic
        # -style `content:` string. Regression test for a request shape that
        # a real API call would otherwise reject outright.
        service.generate_recommendations

        expect(llm_double).to have_received(:chat).with(
          hash_including(
            system: AiRecommendationService::SYSTEM_PROMPT,
            messages: [{ role: 'user', parts: [{ text: kind_of(String) }] }]
          )
        )
      end

      it 'successfully calls LLM, saves recommendations, and increments usage' do
        expect do
          recommendations = service.generate_recommendations
          expect(recommendations.size).to eq(2)
          expect(recommendations.first.category).to eq('UX')
          expect(recommendations.first.priority).to eq(1)
          expect(recommendations.first.description).to eq('ボタンの配置を改善してください')
          expect(recommendations.first.estimated_impact).to eq('高')
        end.to change(AiRecommendation, :count).by(2)
                                               .and change(DailyAiUsage, :count).by(1)

        usage = DailyAiUsage.last
        expect(usage.used_count).to eq(1)
        expect(usage.usage_date).to eq(3.hours.ago.to_date)
      end

      it 'handles markdown block formatting in LLM response' do
        wrapped_json = "```json\n#{response_json}\n```"
        allow(chat_response_double).to receive(:chat_completion).and_return(wrapped_json)

        expect do
          recommendations = service.generate_recommendations
          expect(recommendations.size).to eq(2)
        end.to change(AiRecommendation, :count).by(2)
      end

      it 'raises LLMError if response JSON is invalid or missing recommendations key' do
        allow(chat_response_double).to receive(:chat_completion).and_return('{"invalid": true}')

        expect do
          service.generate_recommendations
        end.to raise_error(AiRecommendationService::LLMError)
      end

      it 'raises LLMError if response is not JSON' do
        allow(chat_response_double).to receive(:chat_completion).and_return('hello world')

        expect do
          service.generate_recommendations
        end.to raise_error(AiRecommendationService::LLMError)
      end

      it 'bubbles up error if LLM call fails' do
        allow(llm_double).to receive(:chat).and_raise(StandardError.new('LLM Down'))

        expect do
          service.generate_recommendations
        end.to raise_error(StandardError, 'LLM Down')
      end

      it 'raises LLMError and does not consume the quota when recommendations array is empty' do
        allow(chat_response_double).to receive(:chat_completion).and_return({ recommendations: [] }.to_json)

        expect do
          expect do
            service.generate_recommendations
          end.to raise_error(AiRecommendationService::LLMError, /2 to 5/)
        end.not_to change(AiRecommendation, :count)

        expect(DailyAiUsage.last.used_count).to eq(0)
      end

      it 'raises LLMError when recommendations array has fewer than 2 items' do
        single_item_json = {
          recommendations: [
            { category: 'UX', priority: 1, description: '改善提案', estimated_impact: '高' }
          ]
        }.to_json
        allow(chat_response_double).to receive(:chat_completion).and_return(single_item_json)

        expect do
          service.generate_recommendations
        end.to raise_error(AiRecommendationService::LLMError, /2 to 5/)
      end

      it 'raises LLMError when a recommendation item has an invalid category' do
        invalid_json = {
          recommendations: [
            { category: 'InvalidCategory', priority: 1, description: '改善提案1', estimated_impact: '高' },
            { category: 'SEO', priority: 2, description: '改善提案2', estimated_impact: '中' }
          ]
        }.to_json
        allow(chat_response_double).to receive(:chat_completion).and_return(invalid_json)

        expect do
          service.generate_recommendations
        end.to raise_error(AiRecommendationService::LLMError, /Invalid recommendation item/)
      end

      it 'raises LLMError when a recommendation item is missing required fields' do
        incomplete_json = {
          recommendations: [
            { category: 'UX', priority: 1, description: '', estimated_impact: '高' },
            { category: 'SEO', priority: 2, description: '改善提案2', estimated_impact: '中' }
          ]
        }.to_json
        allow(chat_response_double).to receive(:chat_completion).and_return(incomplete_json)

        expect do
          service.generate_recommendations
        end.to raise_error(AiRecommendationService::LLMError, /Invalid recommendation item/)
      end
    end

    context 'when daily limit is reached' do
      before do
        # Mark limit as reached for today
        usage_date = 3.hours.ago.to_date
        site.daily_ai_usages.create!(usage_date: usage_date, used_count: 1)
      end

      it 'raises LimitExceededError and does not call LLM' do
        expect(llm_double).not_to receive(:chat)

        expect do
          expect do
            service.generate_recommendations
          end.to raise_error(AiRecommendationService::LimitExceededError, /limit reached/)
        end.not_to change(AiRecommendation, :count)
      end
    end
  end
end
