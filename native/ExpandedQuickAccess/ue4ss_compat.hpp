#pragma once

#include <memory>
#include <string>
#include <string_view>
#include <vector>

#ifndef UE4SS_COMPAT_API
#define UE4SS_COMPAT_API __declspec(dllimport)
#endif

namespace RC
{
    namespace GUI
    {
        class GUITab;
    }

    namespace LuaMadeSimple
    {
        class Lua;
    }

    // This declaration matches CppUserModBase in UE4SS commit f6d5f942.
    class CppUserModBase
    {
      protected:
        std::vector<std::shared_ptr<GUI::GUITab>> GUITabs{};

      public:
        std::wstring ModName{};
        std::wstring ModVersion{};
        std::wstring ModDescription{};
        std::wstring ModAuthors{};
        std::wstring ModIntendedSDKVersion{};

      public:
        UE4SS_COMPAT_API CppUserModBase();
        UE4SS_COMPAT_API virtual ~CppUserModBase();

        virtual void on_update() {}
        virtual void on_unreal_init() {}
        virtual void on_ui_init() {}
        virtual void on_program_start() {}

        virtual void on_lua_start(std::wstring_view,
                                  LuaMadeSimple::Lua&,
                                  LuaMadeSimple::Lua&,
                                  LuaMadeSimple::Lua&,
                                  std::vector<LuaMadeSimple::Lua*>&) {}
        virtual void on_lua_start(LuaMadeSimple::Lua&,
                                  LuaMadeSimple::Lua&,
                                  LuaMadeSimple::Lua&,
                                  std::vector<LuaMadeSimple::Lua*>&) {}
        virtual void on_lua_stop(std::wstring_view,
                                 LuaMadeSimple::Lua&,
                                 LuaMadeSimple::Lua&,
                                 LuaMadeSimple::Lua&,
                                 std::vector<LuaMadeSimple::Lua*>&) {}
        virtual void on_lua_stop(LuaMadeSimple::Lua&,
                                 LuaMadeSimple::Lua&,
                                 LuaMadeSimple::Lua&,
                                 std::vector<LuaMadeSimple::Lua*>&) {}
        virtual void on_dll_load(std::wstring_view) {}
        virtual void render_tab() {}
        virtual void on_lua_start(std::wstring_view,
                                  LuaMadeSimple::Lua&,
                                  LuaMadeSimple::Lua&,
                                  LuaMadeSimple::Lua&,
                                  LuaMadeSimple::Lua*) {}
        virtual void on_lua_start(LuaMadeSimple::Lua&,
                                  LuaMadeSimple::Lua&,
                                  LuaMadeSimple::Lua&,
                                  LuaMadeSimple::Lua*) {}
        virtual void on_lua_stop(std::wstring_view,
                                 LuaMadeSimple::Lua&,
                                 LuaMadeSimple::Lua&,
                                 LuaMadeSimple::Lua&,
                                 LuaMadeSimple::Lua*) {}
        virtual void on_lua_stop(LuaMadeSimple::Lua&,
                                 LuaMadeSimple::Lua&,
                                 LuaMadeSimple::Lua&,
                                 LuaMadeSimple::Lua*) {}
        virtual void on_cpp_mods_loaded() {}
    };
}
