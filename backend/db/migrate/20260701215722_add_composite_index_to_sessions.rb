class AddCompositeIndexToSessions < ActiveRecord::Migration[7.1]
  def change
    # SessionManager#find_or_create_session looks up by site_id + fingerprint,
    # filtered/ordered by last_seen_at, on every accepted event. A composite
    # index serves that lookup directly and also covers the plain site_id
    # queries the old single-column index handled, so it replaces it.
    remove_index :sessions, :site_id
    add_index :sessions, %i[site_id fingerprint last_seen_at], name: 'index_sessions_on_site_fingerprint_last_seen'
  end
end
