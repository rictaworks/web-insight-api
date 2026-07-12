module Api
  module V1
    module Admin
      class UsersController < BaseController
        # GET /api/v1/admin/users
        def index
          @users = User.order(created_at: :asc)
          render json: @users, status: :ok
        end

        # GET /api/v1/admin/users/:id
        def show
          @user = User.find(params[:id])
          render json: @user, status: :ok
        rescue ActiveRecord::RecordNotFound
          render json: { error: 'User not found' }, status: :not_found
        end
      end
    end
  end
end
