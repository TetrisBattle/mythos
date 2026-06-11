local Common    = require("script.virtual_chest.common")
local Inventory = require("script.virtual_chest.inventory")
local Lifecycle = require("script.virtual_chest.lifecycle")
local Logistics = require("script.virtual_chest.logistics")
local Migration = require("script.virtual_chest.migration")

local VirtualChest = {}

VirtualChest.PROTOTYPE = Common.VIRTUAL_CHEST_PROTOTYPE

VirtualChest.getSharedInventory = Inventory.getSharedInventory
VirtualChest.ensureSharedStorage = Inventory.ensureSharedStorage
VirtualChest.normalizePlaceRequests = Inventory.normalizePlaceRequests
VirtualChest.totalItemCount = Inventory.totalItemCount
VirtualChest.findInventories = Inventory.findInventories
VirtualChest.sortedInventories = Inventory.sortedInventories
VirtualChest.getItemCountFromInventories = Inventory.getItemCountFromInventories
VirtualChest.removeItemsFromInventories = Inventory.removeItemsFromInventories
VirtualChest.insertItemsIntoInventories = Inventory.insertItemsIntoInventories
VirtualChest.getItemCount = Inventory.getItemCount
VirtualChest.removeItems = Inventory.removeItems
VirtualChest.insertStack = Inventory.insertStack
VirtualChest.insertItems = Inventory.insertItems

VirtualChest.isVirtualChestEntity = Lifecycle.isVirtualChestEntity
VirtualChest.ensureLinkId = Lifecycle.ensureLinkId
VirtualChest.register = Lifecycle.register
VirtualChest.unregister = Lifecycle.unregister
VirtualChest.onBuilt = Lifecycle.onBuilt
VirtualChest.onRemoved = Lifecycle.onRemoved
VirtualChest.bootstrapExisting = Lifecycle.bootstrapExisting
VirtualChest.tickSlow = Lifecycle.tickSlow

VirtualChest.ghostRequests = Logistics.ghostRequests
VirtualChest.sortedInventoriesForMythos = Logistics.sortedInventoriesForMythos
VirtualChest.tryMineEntity = Logistics.tryMineEntity

VirtualChest.purgeAll = Migration.purgeAll

return VirtualChest
