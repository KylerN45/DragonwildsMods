#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <Windows.h>

#include <array>
#include <atomic>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <string>
#include <vector>

#include "route_layout.hpp"
#include "ue4ss_compat.hpp"

namespace
{
    constexpr auto MOD_VERSION = L"0.2.0";
    constexpr std::size_t CALL_INSTRUCTION_SIZE = 5;
    constexpr std::size_t THUNK_SIZE = 15;

    using HandleInternalUseItem = void(__fastcall*)(void*, std::int32_t, std::uint32_t);

    HMODULE g_this_module = nullptr;
    HANDLE g_log_file = INVALID_HANDLE_VALUE;
    HandleInternalUseItem g_handle_internal_use_item = nullptr;
    std::atomic<std::uint64_t> g_routed_selections{0};

    struct Pattern
    {
        const unsigned char* bytes;
        const char* mask;
        std::size_t size;
    };

    struct CallPatch
    {
        unsigned char* address{};
        std::array<unsigned char, CALL_INSTRUCTION_SIZE> original{};
        std::array<unsigned char, CALL_INSTRUCTION_SIZE> replacement{};
        void* thunk{};
        bool active{};
    };

    CallPatch g_selection_patch{};

    // Unique in the current shipping executable. The first call is the direct
    // UInventoryUIAPI::HandleInternalUseItem call. The second call closes the
    // radial selection. Both relative displacements are intentionally masked.
    constexpr unsigned char SELECTION_CALLSITE_BYTES[] = {
        0x45, 0x33, 0xC0,             // xor r8d,r8d (QuickAction)
        0x8B, 0xD7,                   // mov edx,edi (selected slice)
        0x48, 0x8B, 0xC8,             // mov rcx,rax (InventoryUIAPI)
        0xE8, 0x00, 0x00, 0x00, 0x00,
        0x48, 0x8B, 0xCB,
        0xE8, 0x00, 0x00, 0x00, 0x00,
    };
    constexpr char SELECTION_CALLSITE_MASK[] = "xxxxxxxxx????xxxx????";

    // Unique prologue of UInventoryUIAPI::HandleInternalUseItem. The resolved
    // target of the callsite must equal this match before any byte is changed.
    constexpr unsigned char HANDLE_INTERNAL_USE_ITEM_BYTES[] = {
        0x48, 0x89, 0x5C, 0x24, 0x10,
        0x48, 0x89, 0x6C, 0x24, 0x18,
        0x48, 0x89, 0x74, 0x24, 0x20,
        0x57,
        0x48, 0x83, 0xEC, 0x40,
        0x33, 0xF6,
        0x45, 0x0F, 0xB6, 0xC8,
        0x8B, 0xDA,
        0x48, 0x8B, 0xF9,
    };
    constexpr char HANDLE_INTERNAL_USE_ITEM_MASK[] = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";

    constexpr Pattern SELECTION_CALLSITE_PATTERN{
        SELECTION_CALLSITE_BYTES,
        SELECTION_CALLSITE_MASK,
        sizeof(SELECTION_CALLSITE_BYTES),
    };
    constexpr Pattern HANDLE_INTERNAL_USE_ITEM_PATTERN{
        HANDLE_INTERNAL_USE_ITEM_BYTES,
        HANDLE_INTERNAL_USE_ITEM_MASK,
        sizeof(HANDLE_INTERNAL_USE_ITEM_BYTES),
    };

    void write_log(const char* format, ...)
    {
        std::array<char, 1024> message{};
        va_list args;
        va_start(args, format);
        const int length = std::vsnprintf(message.data(), message.size(), format, args);
        va_end(args);

        if (length <= 0)
        {
            return;
        }

        const auto used = static_cast<std::size_t>(length) < message.size()
            ? static_cast<std::size_t>(length)
            : message.size() - 1;
        OutputDebugStringA(message.data());
        std::fwrite(message.data(), 1, used, stdout);
        std::fflush(stdout);

        if (g_log_file != INVALID_HANDLE_VALUE)
        {
            DWORD written = 0;
            WriteFile(g_log_file, message.data(), static_cast<DWORD>(used), &written, nullptr);
            FlushFileBuffers(g_log_file);
        }
    }

    void open_log()
    {
        std::array<wchar_t, 32768> path_buffer{};
        const DWORD length = GetModuleFileNameW(
            g_this_module,
            path_buffer.data(),
            static_cast<DWORD>(path_buffer.size()));
        if (length == 0 || length >= path_buffer.size())
        {
            return;
        }

        std::wstring path(path_buffer.data(), length);
        const auto dlls_separator = path.find_last_of(L"\\/");
        if (dlls_separator == std::wstring::npos)
        {
            return;
        }
        path.resize(dlls_separator);

        const auto mod_separator = path.find_last_of(L"\\/");
        if (mod_separator == std::wstring::npos)
        {
            return;
        }
        path.resize(mod_separator + 1);
        path += L"ExpandedQuickAccess.log";

        g_log_file = CreateFileW(
            path.c_str(),
            GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            nullptr,
            CREATE_ALWAYS,
            FILE_ATTRIBUTE_NORMAL,
            nullptr);
    }

    bool matches(const unsigned char* address, const Pattern& pattern)
    {
        for (std::size_t index = 0; index < pattern.size; ++index)
        {
            if (pattern.mask[index] == 'x' && address[index] != pattern.bytes[index])
            {
                return false;
            }
        }
        return true;
    }

    std::vector<unsigned char*> find_pattern(const Pattern& pattern)
    {
        std::vector<unsigned char*> matches_found;
        auto* image = reinterpret_cast<unsigned char*>(GetModuleHandleW(nullptr));
        if (!image)
        {
            return matches_found;
        }

        const auto* dos_header = reinterpret_cast<const IMAGE_DOS_HEADER*>(image);
        if (dos_header->e_magic != IMAGE_DOS_SIGNATURE)
        {
            return matches_found;
        }

        const auto* nt_headers = reinterpret_cast<const IMAGE_NT_HEADERS64*>(
            image + dos_header->e_lfanew);
        if (nt_headers->Signature != IMAGE_NT_SIGNATURE
            || nt_headers->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC)
        {
            return matches_found;
        }

        const auto* section = IMAGE_FIRST_SECTION(nt_headers);
        for (WORD section_index = 0;
             section_index < nt_headers->FileHeader.NumberOfSections;
             ++section_index, ++section)
        {
            if ((section->Characteristics & IMAGE_SCN_MEM_EXECUTE) == 0)
            {
                continue;
            }

            const std::size_t section_size = section->Misc.VirtualSize;
            if (section_size < pattern.size)
            {
                continue;
            }

            auto* section_start = image + section->VirtualAddress;
            for (std::size_t offset = 0; offset <= section_size - pattern.size; ++offset)
            {
                if (matches(section_start + offset, pattern))
                {
                    matches_found.push_back(section_start + offset);
                }
            }
        }
        return matches_found;
    }

    bool write_bytes(void* address, const void* bytes, std::size_t size)
    {
        DWORD old_protection = 0;
        if (!VirtualProtect(address, size, PAGE_EXECUTE_READWRITE, &old_protection))
        {
            return false;
        }

        std::memcpy(address, bytes, size);
        if (!FlushInstructionCache(GetCurrentProcess(), address, size))
        {
            write_log("[ExpandedQuickAccess] Warning: Windows did not confirm the instruction-cache flush.\n");
        }

        DWORD unused = 0;
        if (!VirtualProtect(address, size, old_protection, &unused))
        {
            write_log("[ExpandedQuickAccess] Warning: Windows did not restore the original page protection.\n");
        }
        return true;
    }

    bool relative_call_fits(const unsigned char* instruction, const void* target)
    {
        const auto from = reinterpret_cast<std::intptr_t>(instruction + CALL_INSTRUCTION_SIZE);
        const auto to = reinterpret_cast<std::intptr_t>(target);
        const auto displacement = to - from;
        return displacement >= std::numeric_limits<std::int32_t>::min()
            && displacement <= std::numeric_limits<std::int32_t>::max();
    }

    void* allocate_thunk_near(unsigned char* call_instruction)
    {
        SYSTEM_INFO system_info{};
        GetSystemInfo(&system_info);
        const auto granularity = static_cast<std::uintptr_t>(system_info.dwAllocationGranularity);
        const auto page_size = static_cast<std::size_t>(system_info.dwPageSize);
        const auto call_end = reinterpret_cast<std::uintptr_t>(
            call_instruction + CALL_INSTRUCTION_SIZE);
        const auto maximum_address = reinterpret_cast<std::uintptr_t>(
            system_info.lpMaximumApplicationAddress);
        const auto relative_limit = static_cast<std::uintptr_t>(
            std::numeric_limits<std::int32_t>::max());
        const auto upper_bound = call_end > maximum_address - relative_limit
            ? maximum_address
            : call_end + relative_limit;

        std::uintptr_t cursor = call_end;
        while (cursor < upper_bound)
        {
            MEMORY_BASIC_INFORMATION region{};
            if (VirtualQuery(reinterpret_cast<void*>(cursor), &region, sizeof(region)) == 0)
            {
                break;
            }

            const auto region_start = reinterpret_cast<std::uintptr_t>(region.BaseAddress);
            const auto region_end = region_start + region.RegionSize;
            if (region.State == MEM_FREE)
            {
                const auto unaligned = region_start > cursor ? region_start : cursor;
                const auto candidate = (unaligned + granularity - 1) & ~(granularity - 1);
                if (candidate <= upper_bound
                    && candidate <= region_end
                    && page_size <= region_end - candidate)
                {
                    void* allocation = VirtualAlloc(
                        reinterpret_cast<void*>(candidate),
                        page_size,
                        MEM_RESERVE | MEM_COMMIT,
                        PAGE_READWRITE);
                    if (allocation && relative_call_fits(call_instruction, allocation))
                    {
                        return allocation;
                    }
                    if (allocation)
                    {
                        VirtualFree(allocation, 0, MEM_RELEASE);
                    }
                }
            }

            if (region_end <= cursor)
            {
                break;
            }
            cursor = region_end;
        }
        return nullptr;
    }

    unsigned char* resolve_relative_call(unsigned char* call_instruction)
    {
        if (!call_instruction || call_instruction[0] != 0xE8)
        {
            return nullptr;
        }
        std::int32_t displacement = 0;
        std::memcpy(&displacement, call_instruction + 1, sizeof(displacement));
        return call_instruction + CALL_INSTRUCTION_SIZE + displacement;
    }

    extern "C" void __fastcall route_selected_item(
        void* inventory_api,
        std::int32_t selected_slice,
        std::uint32_t original_type,
        void* radial) noexcept
    {
        std::int32_t inventory_index = selected_slice;
        std::uint32_t inventory_type = original_type;
        const bool routed = ExpandedQuickAccess::resolve_inventory_route(
            radial,
            selected_slice,
            inventory_index,
            inventory_type);

        if (routed)
        {
            const auto prior_count = g_routed_selections.fetch_add(1, std::memory_order_relaxed);
            if (prior_count == 0)
            {
                write_log(
                    "[ExpandedQuickAccess] Routed the first inventory-page selection (slice %d, inventory index %d).\n",
                    selected_slice,
                    inventory_index);
            }
        }

        g_handle_internal_use_item(inventory_api, inventory_index, inventory_type);
    }

    bool write_thunk(void* allocation)
    {
        if (!allocation)
        {
            return false;
        }

        // mov r9,rbx; mov rax,<route_selected_item>; jmp rax
        std::array<unsigned char, THUNK_SIZE> thunk{
            0x4C, 0x8B, 0xCB,
            0x48, 0xB8,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0xFF, 0xE0,
        };
        const auto handler = reinterpret_cast<std::uintptr_t>(&route_selected_item);
        std::memcpy(thunk.data() + 5, &handler, sizeof(handler));
        std::memcpy(allocation, thunk.data(), thunk.size());

        DWORD old_protection = 0;
        if (!VirtualProtect(allocation, thunk.size(), PAGE_EXECUTE_READ, &old_protection))
        {
            return false;
        }
        return FlushInstructionCache(GetCurrentProcess(), allocation, thunk.size()) != FALSE;
    }

    void release_thunk(CallPatch& patch)
    {
        if (patch.thunk)
        {
            VirtualFree(patch.thunk, 0, MEM_RELEASE);
            patch.thunk = nullptr;
        }
    }

    void restore_selection_patch()
    {
        if (!g_selection_patch.active)
        {
            release_thunk(g_selection_patch);
            return;
        }

        if (std::memcmp(
                g_selection_patch.address,
                g_selection_patch.replacement.data(),
                g_selection_patch.replacement.size()) != 0)
        {
            write_log(
                "[ExpandedQuickAccess] The selection call changed before restoration. The mod did not overwrite it.\n");
            // The call might still reach this thunk. Keep its memory allocated.
            g_selection_patch.active = false;
            return;
        }

        if (!write_bytes(
                g_selection_patch.address,
                g_selection_patch.original.data(),
                g_selection_patch.original.size()))
        {
            write_log(
                "[ExpandedQuickAccess] Could not restore the selection call. Close the game before you remove the mod.\n");
            return;
        }

        g_selection_patch.active = false;
        release_thunk(g_selection_patch);
    }

    bool install_selection_patch()
    {
        const auto callsite_matches = find_pattern(SELECTION_CALLSITE_PATTERN);
        const auto target_matches = find_pattern(HANDLE_INTERNAL_USE_ITEM_PATTERN);
        if (callsite_matches.size() != 1 || target_matches.size() != 1)
        {
            write_log(
                "[ExpandedQuickAccess] Version 0.2.0 is inactive. Expected one radial callsite and one inventory-use target. Found %zu and %zu.\n",
                callsite_matches.size(),
                target_matches.size());
            return false;
        }

        auto* call_instruction = callsite_matches.front() + 8;
        auto* resolved_target = resolve_relative_call(call_instruction);
        if (resolved_target != target_matches.front())
        {
            write_log(
                "[ExpandedQuickAccess] Version 0.2.0 is inactive. The radial call did not resolve to the verified inventory-use function.\n");
            return false;
        }

        g_handle_internal_use_item = reinterpret_cast<HandleInternalUseItem>(resolved_target);
        g_selection_patch.address = call_instruction;
        std::memcpy(
            g_selection_patch.original.data(),
            call_instruction,
            g_selection_patch.original.size());

        g_selection_patch.thunk = allocate_thunk_near(call_instruction);
        if (!g_selection_patch.thunk || !write_thunk(g_selection_patch.thunk))
        {
            release_thunk(g_selection_patch);
            write_log(
                "[ExpandedQuickAccess] Version 0.2.0 is inactive. Could not create a nearby selection thunk.\n");
            return false;
        }

        if (!relative_call_fits(call_instruction, g_selection_patch.thunk))
        {
            release_thunk(g_selection_patch);
            write_log(
                "[ExpandedQuickAccess] Version 0.2.0 is inactive. The selection thunk is outside relative-call range.\n");
            return false;
        }

        g_selection_patch.replacement[0] = 0xE8;
        const auto displacement64 = reinterpret_cast<std::intptr_t>(g_selection_patch.thunk)
            - reinterpret_cast<std::intptr_t>(call_instruction + CALL_INSTRUCTION_SIZE);
        const auto displacement = static_cast<std::int32_t>(displacement64);
        std::memcpy(
            g_selection_patch.replacement.data() + 1,
            &displacement,
            sizeof(displacement));

        if (!write_bytes(
                call_instruction,
                g_selection_patch.replacement.data(),
                g_selection_patch.replacement.size())
            || std::memcmp(
                call_instruction,
                g_selection_patch.replacement.data(),
                g_selection_patch.replacement.size()) != 0)
        {
            if (std::memcmp(
                    call_instruction,
                    g_selection_patch.replacement.data(),
                    g_selection_patch.replacement.size()) == 0)
            {
                g_selection_patch.active = true;
                restore_selection_patch();
            }
            else
            {
                release_thunk(g_selection_patch);
            }
            write_log(
                "[ExpandedQuickAccess] Version 0.2.0 is inactive. Could not patch the radial selection call.\n");
            return false;
        }

        g_selection_patch.active = true;
        write_log(
            "[ExpandedQuickAccess] Version 0.2.0 active. Inventory-page selection routing is enabled.\n");
        return true;
    }
}

class ExpandedQuickAccessMod final : public RC::CppUserModBase
{
  public:
    ExpandedQuickAccessMod()
    {
        ModName = L"ExpandedQuickAccess";
        ModVersion = MOD_VERSION;
        ModDescription = L"Adds the main inventory rows to the quick-access radial.";
        ModAuthors = L"Kyler";

        open_log();
        install_selection_patch();
    }

    ~ExpandedQuickAccessMod() override
    {
        restore_selection_patch();
        write_log(
            "[ExpandedQuickAccess] Native selection router stopped after %llu routed selections.\n",
            static_cast<unsigned long long>(g_routed_selections.load(std::memory_order_relaxed)));

        if (g_log_file != INVALID_HANDLE_VALUE)
        {
            CloseHandle(g_log_file);
            g_log_file = INVALID_HANDLE_VALUE;
        }
    }
};

#define MOD_API extern "C" __declspec(dllexport)

MOD_API RC::CppUserModBase* start_mod()
{
    return new ExpandedQuickAccessMod();
}

MOD_API void uninstall_mod(RC::CppUserModBase* mod)
{
    delete mod;
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        g_this_module = module;
        DisableThreadLibraryCalls(module);
    }
    return TRUE;
}
