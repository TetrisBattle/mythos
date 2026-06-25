local StorageBootstrap = {}

function StorageBootstrap.init()
	storage.mythoi                 = {}
	storage.saved_dimensions       = {}
	storage.pending_player_restore = {}
	storage.viewing                = {}
	storage.remote_view_returns    = {}
	storage.gate_hover_borders     = {}
	storage.pending_resize_gui     = {}
	storage.virtualChests          = {}
	storage.mythos_next_snapshot_id = 0
	storage.mythos_pending_paste    = nil
end

return StorageBootstrap
