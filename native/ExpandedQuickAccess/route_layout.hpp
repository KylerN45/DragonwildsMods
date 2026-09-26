#pragma once

#include <cstddef>
#include <cstdint>
#include <excpt.h>

namespace ExpandedQuickAccess
{
    inline constexpr std::size_t QUICK_ACCESS_RADIAL_SLICES_OFFSET = 0x5A8;
    inline constexpr std::size_t QUICK_ACCESS_RADIAL_SLICE_COUNT_OFFSET = 0x5B0;
    inline constexpr std::size_t QUICK_ACCESS_SLICE_SLOT_OFFSET = 0x428;
    inline constexpr std::size_t SLOT_PAYLOAD_OFFSET = 0x1860;
    inline constexpr std::size_t INVENTORY_INDEX_OFFSET = 0x40;
    inline constexpr std::size_t OWNING_INVENTORY_TYPE_OFFSET = 0x44;

    inline constexpr std::int32_t SLOTS_PER_PAGE = 8;
    inline constexpr std::int32_t MAIN_INVENTORY_SLOT_COUNT = 24;
    inline constexpr std::uint8_t INVENTORY_ITEMS = 1;

    // The offsets above come from the current game's generated reflection
    // descriptors. Native accessors in the shipping executable independently
    // use SlotPayload +0x1860, InventoryIndex +0x40, and type +0x44.
    inline bool resolve_inventory_route(
        void* radial,
        std::int32_t selected_slice,
        std::int32_t& inventory_index,
        std::uint32_t& inventory_type) noexcept
    {
        __try
        {
            if (!radial || selected_slice < 0 || selected_slice >= SLOTS_PER_PAGE)
            {
                return false;
            }

            auto* radial_bytes = static_cast<std::byte*>(radial);
            const auto slice_count = *reinterpret_cast<const std::int32_t*>(
                radial_bytes + QUICK_ACCESS_RADIAL_SLICE_COUNT_OFFSET);
            if (slice_count != SLOTS_PER_PAGE)
            {
                return false;
            }

            auto** slices = *reinterpret_cast<void***>(
                radial_bytes + QUICK_ACCESS_RADIAL_SLICES_OFFSET);
            if (!slices)
            {
                return false;
            }

            void* slice = slices[selected_slice];
            if (!slice)
            {
                return false;
            }

            auto* slice_bytes = static_cast<std::byte*>(slice);
            void* slot = *reinterpret_cast<void**>(
                slice_bytes + QUICK_ACCESS_SLICE_SLOT_OFFSET);
            if (!slot)
            {
                return false;
            }

            auto* slot_bytes = static_cast<std::byte*>(slot);
            void* payload = *reinterpret_cast<void**>(slot_bytes + SLOT_PAYLOAD_OFFSET);
            if (!payload)
            {
                return false;
            }

            auto* payload_bytes = static_cast<std::byte*>(payload);
            const auto candidate_index = *reinterpret_cast<const std::int32_t*>(
                payload_bytes + INVENTORY_INDEX_OFFSET);
            const auto candidate_type = *reinterpret_cast<const std::uint8_t*>(
                payload_bytes + OWNING_INVENTORY_TYPE_OFFSET);

            if (candidate_type != INVENTORY_ITEMS
                || candidate_index < 0
                || candidate_index >= MAIN_INVENTORY_SLOT_COUNT)
            {
                return false;
            }

            inventory_index = candidate_index;
            inventory_type = candidate_type;
            return true;
        }
        __except (EXCEPTION_EXECUTE_HANDLER)
        {
            return false;
        }
    }
}
