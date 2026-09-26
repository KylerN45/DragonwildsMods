#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <Windows.h>

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>

#include "route_layout.hpp"

namespace
{
    template <typename T, std::size_t Size>
    void store(std::array<std::byte, Size>& buffer, std::size_t offset, const T& value)
    {
        std::memcpy(buffer.data() + offset, &value, sizeof(value));
    }

    struct Fixture
    {
        alignas(8) std::array<std::byte, 0x5C0> radial{};
        alignas(8) std::array<std::byte, 0x430> slice{};
        alignas(8) std::array<std::byte, 0x1870> slot{};
        alignas(8) std::array<std::byte, 0x50> payload{};
        std::array<void*, ExpandedQuickAccess::SLOTS_PER_PAGE> slices{};

        Fixture()
        {
            slices[3] = slice.data();
            void** slice_data = slices.data();
            store(radial, ExpandedQuickAccess::QUICK_ACCESS_RADIAL_SLICES_OFFSET, slice_data);

            const std::int32_t slice_count = ExpandedQuickAccess::SLOTS_PER_PAGE;
            store(radial, ExpandedQuickAccess::QUICK_ACCESS_RADIAL_SLICE_COUNT_OFFSET, slice_count);

            void* slot_pointer = slot.data();
            store(slice, ExpandedQuickAccess::QUICK_ACCESS_SLICE_SLOT_OFFSET, slot_pointer);

            void* payload_pointer = payload.data();
            store(slot, ExpandedQuickAccess::SLOT_PAYLOAD_OFFSET, payload_pointer);
        }

        void set_payload(std::int32_t index, std::uint8_t type)
        {
            store(payload, ExpandedQuickAccess::INVENTORY_INDEX_OFFSET, index);
            store(payload, ExpandedQuickAccess::OWNING_INVENTORY_TYPE_OFFSET, type);
        }
    };

    bool expect(bool condition, const char* message)
    {
        if (!condition)
        {
            std::fprintf(stderr, "Routing test failed: %s\n", message);
            return false;
        }
        return true;
    }
}

int main()
{
    Fixture fixture;
    std::int32_t index = -1;
    std::uint32_t type = 0;

    fixture.set_payload(0, ExpandedQuickAccess::INVENTORY_ITEMS);
    if (!expect(ExpandedQuickAccess::resolve_inventory_route(
            fixture.radial.data(), 3, index, type), "first main slot was not routed")
        || !expect(index == 0, "first main slot index changed")
        || !expect(type == ExpandedQuickAccess::INVENTORY_ITEMS, "inventory type changed"))
    {
        return 1;
    }

    fixture.set_payload(23, ExpandedQuickAccess::INVENTORY_ITEMS);
    if (!expect(ExpandedQuickAccess::resolve_inventory_route(
            fixture.radial.data(), 3, index, type), "last main slot was not routed")
        || !expect(index == 23, "last main slot index changed"))
    {
        return 1;
    }

    fixture.set_payload(7, 0);
    if (!expect(!ExpandedQuickAccess::resolve_inventory_route(
            fixture.radial.data(), 3, index, type), "quick slot was rerouted"))
    {
        return 1;
    }

    fixture.set_payload(24, ExpandedQuickAccess::INVENTORY_ITEMS);
    if (!expect(!ExpandedQuickAccess::resolve_inventory_route(
            fixture.radial.data(), 3, index, type), "out-of-range inventory slot was routed"))
    {
        return 1;
    }

    fixture.set_payload(7, ExpandedQuickAccess::INVENTORY_ITEMS);
    if (!expect(!ExpandedQuickAccess::resolve_inventory_route(
            fixture.radial.data(), 8, index, type), "out-of-range slice was routed")
        || !expect(!ExpandedQuickAccess::resolve_inventory_route(
            nullptr, 3, index, type), "null radial was routed"))
    {
        return 1;
    }

    const std::int32_t wrong_count = 7;
    store(fixture.radial, ExpandedQuickAccess::QUICK_ACCESS_RADIAL_SLICE_COUNT_OFFSET, wrong_count);
    if (!expect(!ExpandedQuickAccess::resolve_inventory_route(
            fixture.radial.data(), 3, index, type), "wrong slice count was routed"))
    {
        return 1;
    }

    std::puts("Native routing tests passed.");
    return 0;
}
