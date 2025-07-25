#!/usr/bin/env bash

# This file is part of The RetroPie Project
#
# The RetroPie Project is the legal property of its developers, whose names are
# too numerous to list here. Please refer to the COPYRIGHT.md file distributed with this source.
#
# See the LICENSE.md file at the top-level directory of this distribution and
# at https://raw.githubusercontent.com/RetroPie/RetroPie-Setup/master/LICENSE.md
#

rp_module_id="retroarch"
rp_module_desc="RetroArch - frontend to the libretro emulator cores - required by all lr-* emulators"
rp_module_licence="GPL3 https://raw.githubusercontent.com/libretro/RetroArch/master/COPYING"
rp_module_repo="git https://github.com/retropie/RetroArch.git retropie-v1.19.0"
rp_module_section="core"

function depends_retroarch() {
    local depends=(libudev-dev libxkbcommon-dev libsdl2-dev libasound2-dev libusb-1.0-0-dev)
    isPlatform "dispmanx" && depends+=(libraspberrypi-dev)
    isPlatform "gles" && ! isPlatform "vero4k" && depends+=(libgles2-mesa-dev)
    isPlatform "mesa" && depends+=(libx11-xcb-dev)
    isPlatform "mali" && depends+=(mali-fbdev)
    isPlatform "x11" && depends+=(libx11-xcb-dev libpulse-dev)
    isPlatform "vulkan" && depends+=(libvulkan-dev mesa-vulkan-drivers)
    isPlatform "vero4k" && depends+=(vero3-userland-dev-osmc zlib1g-dev libfreetype6-dev)
    isPlatform "kms" && depends+=(libgbm-dev)

    if [[ "$__os_debian_ver" -ge 9 ]]; then
        depends+=(libavcodec-dev libavformat-dev libavdevice-dev)
    fi

    getDepends "${depends[@]}"
}

function sources_retroarch() {
    gitPullOrClone
}

function build_retroarch() {
    local params=(--disable-sdl --enable-sdl2 --disable-oss --disable-al --disable-jack --disable-qt)
    if ! isPlatform "x11"; then
        params+=(--disable-pulse)
        ! isPlatform "mesa" && params+=(--disable-x11)
    fi
    if [[ "$__os_debian_ver" -lt 9 ]]; then
        params+=(--disable-ffmpeg)
    fi
    isPlatform "gles" && params+=(--enable-opengles)
    if isPlatform "gles3"; then
        params+=(--enable-opengles3)
        isPlatform "gles31" && params+=(--enable-opengles3_1)
        isPlatform "gles32" && params+=(--enable-opengles3_2)
    fi
    isPlatform "videocore" && params+=(--disable-crtswitchres)
    isPlatform "rpi" && isPlatform "mesa" && params+=(--disable-videocore)
    # Temporarily block dispmanx support for fkms until upstream support is fixed
    isPlatform "dispmanx" && ! isPlatform "kms" && params+=(--enable-dispmanx --disable-opengl1)
    isPlatform "mali" && params+=(--enable-mali_fbdev)
    isPlatform "kms" && params+=(--enable-kms --enable-egl)
    isPlatform "arm" && params+=(--enable-floathard)
    isPlatform "neon" && params+=(--enable-neon)
    isPlatform "vulkan" && params+=(--enable-vulkan) || params+=(--disable-vulkan)
    ! isPlatform "x11" && params+=(--disable-wayland)
    isPlatform "vero4k" && params+=(--enable-mali_fbdev --with-opengles_libs='-L/opt/vero3/lib')
    ./configure --prefix="$md_inst" "${params[@]}"
    make clean
    make
    md_ret_require="$md_build/retroarch"
}

function install_retroarch() {
    make install
    md_ret_files=(
        'retroarch.cfg'
    )
}

function update_shaders_retroarch() {
    local dir="$configdir/all/retroarch/shaders"
    local branch=""
    isPlatform "rpi" && branch="rpi"
    # remove if not git repository for fresh checkout
    [[ ! -d "$dir/.git" ]] && rm -rf "$dir"
    gitPullOrClone "$dir" https://github.com/RetroPie/common-shaders.git "$branch"
    chown -R "$__user":"$__group" "$dir"
}

function update_overlays_retroarch() {
    local dir="$configdir/all/retroarch/overlay"
    # remove if not a git repository for fresh checkout
    [[ ! -d "$dir/.git" ]] && rm -rf "$dir"
    gitPullOrClone "$dir" https://github.com/libretro/common-overlays.git
    chown -R "$__user":"$__group" "$dir"
}

function update_joypad_autoconfigs_retroarch() {
    gitPullOrClone "$md_build/autoconfigs" https://github.com/libretro/retroarch-joypad-autoconfig.git
    cp -a "$md_build/autoconfigs/." "$md_inst/autoconfig-presets/"
}

function update_assets_retroarch() {
    local dir="$configdir/all/retroarch/assets"
    # remove if not a git repository for fresh checkout
    [[ ! -d "$dir/.git" ]] && rm -rf "$dir"
    gitPullOrClone "$dir" https://github.com/libretro/retroarch-assets.git
    chown -R "$__user":"$__group" "$dir"
}

function update_core_info_retroarch() {
    local dir="$configdir/all/retroarch/cores"
    # remove if not a git repository and do a fresh checkout
    [[ ! -d "$dir/.git" ]] && rm -fr "$dir"
    # remove our locally generated `.info` files, just in case upstream adds them
    [[ -d "$dir/.git" ]] && git -C "$dir" clean -q -f "*.info"
    gitPullOrClone "$dir" https://github.com/libretro/libretro-core-info.git
    # add our info files for cores not included in the upstream repo
    cp --update "$md_data"/*.info "$dir"
    chown -R "$__user":"$__group" "$dir"
}

function install_minimal_assets_retroarch() {
    local dir="$configdir/all/retroarch/assets"
    [[ -d "$dir/.git" ]] && return
    [[ ! -d "$dir" ]] && mkUserDir "$dir"
    downloadAndExtract "$__binary_base_url/retroarch-minimal-assets.tar.gz" "$dir"
    chown -R "$__user":"$__group" "$dir"
}

function _package_minimal_assets_retroarch() {
    gitPullOrClone "$md_build/assets" https://github.com/libretro/retroarch-assets.git
    mkdir -p "$__tmpdir/archives"
    local archive="$__tmpdir/archives/retroarch-minimal-assets.tar.gz"
    rm -f "$archive"
    tar cvzf "$archive" -C "$md_build/assets" ozone menu_widgets xmb/monochrome
}

function configure_retroarch() {
    [[ "$md_mode" == "remove" ]] && return

    addUdevInputRules

    # move / symlink the retroarch configuration
    moveConfigDir "$home/.config/retroarch" "$configdir/all/retroarch"

    # move / symlink our old retroarch-joypads folder
    moveConfigDir "$configdir/all/retroarch-joypads" "$configdir/all/retroarch/autoconfig"

    # move / symlink old assets / overlays and shader folder
    moveConfigDir "$md_inst/assets" "$configdir/all/retroarch/assets"
    moveConfigDir "$md_inst/overlays" "$configdir/all/retroarch/overlay"
    moveConfigDir "$md_inst/shader" "$configdir/all/retroarch/shaders"

    # install shaders by default
    update_shaders_retroarch

    # install minimal assets
    install_minimal_assets_retroarch

    # install core info files
    update_core_info_retroarch

    # install joypad autoconfig presets
    update_joypad_autoconfigs_retroarch

    local config="$(mktemp)"

    cp "$md_inst/retroarch.cfg" "$config"

    # query ES A/B key swap configuration
    local es_swap="false"
    getAutoConf "es_swap_a_b" && es_swap="true"

    # configure default options
    iniConfig " = " '"' "$config"
    iniSet "cache_directory" "/tmp/retroarch"
    iniSet "system_directory" "$biosdir"
    iniSet "config_save_on_exit" "false"
    iniSet "video_aspect_ratio_auto" "true"
    if ! isPlatform "x86"; then
        iniSet "video_threaded" "true"
    fi

    iniSet "video_font_size" "24"
    iniSet "core_options_path" "$configdir/all/retroarch-core-options.cfg"
    iniSet "global_core_options" "true"
    isPlatform "x11" && iniSet "video_fullscreen" "true"
    isPlatform "mesa" && iniSet "video_fullscreen" "true"

    # set default render resolution to 640x480 for rpi1
    if isPlatform "videocore" && isPlatform "rpi1"; then
        iniSet "video_fullscreen_x" "640"
        iniSet "video_fullscreen_y" "480"
    fi

    # enable hotkey ("select" button)
    iniSet "input_enable_hotkey" "nul"
    iniSet "input_exit_emulator" "escape"

    # enable and configure rewind feature
    iniSet "rewind_enable" "false"
    iniSet "rewind_buffer_size" "10"
    iniSet "rewind_granularity" "2"
    iniSet "input_rewind" "r"

    # enable gpu screenshots
    iniSet "video_gpu_screenshot" "true"

    # enable and configure shaders
    iniSet "input_shader_next" "m"
    iniSet "input_shader_prev" "n"

    # configure keyboard mappings
    iniSet "input_player1_a" "x"
    iniSet "input_player1_b" "z"
    iniSet "input_player1_y" "a"
    iniSet "input_player1_x" "s"
    iniSet "input_player1_start" "enter"
    iniSet "input_player1_select" "rshift"
    iniSet "input_player1_l" "q"
    iniSet "input_player1_r" "w"
    iniSet "input_player1_left" "left"
    iniSet "input_player1_right" "right"
    iniSet "input_player1_up" "up"
    iniSet "input_player1_down" "down"

    # input settings
    iniSet "input_autodetect_enable" "true"
    iniSet "auto_remaps_enable" "true"
    iniSet "input_joypad_driver" "udev"
    iniSet "all_users_control_menu" "true"
    iniSet "remap_save_on_exit" "false"

    # rgui by default
    iniSet "menu_driver" "rgui"
    iniSet "rgui_aspect_ratio_lock" "2"
    iniSet "rgui_browser_directory" "$romdir"
    iniSet "rgui_switch_icons" "false"
    iniSet "menu_rgui_shadows" "true"
    iniSet "rgui_menu_color_theme" "29" # Tango Dark theme

    # hide online updater menu options and the restart option
    iniSet "menu_show_core_updater" "false"
    iniSet "menu_show_online_updater" "false"
    iniSet "menu_show_restart_retroarch" "false"
    # disable the search action
    iniSet "menu_disable_search_button" "true"

    # remove some rarely used entries from the quick menu
    iniSet "quick_menu_show_close_content" "false"
    iniSet "quick_menu_show_add_to_favorites" "false"
    iniSet "quick_menu_show_replay" "false"
    iniSet "quick_menu_show_start_recording" "false"
    iniSet "quick_menu_show_start_streaming" "false"
    iniSet "menu_show_overlays" "false"

    # disable the load notification message with core and game info
    iniSet "menu_show_load_content_animation" "false"
    # disable core cache file
    iniSet "core_info_cache_enable" "false"
    # disable game runtime logging
    iniSet "content_runtime_log" "false"

    # disable unnecessary xmb menu tabs
    iniSet "xmb_show_add" "false"
    iniSet "xmb_show_history" "false"
    iniSet "xmb_show_images" "false"
    iniSet "xmb_show_music" "false"

    # disable xmb menu driver icon shadows
    iniSet "xmb_shadows_enable" "false"

    # swap A/B buttons based on ES configuration
    iniSet "menu_swap_ok_cancel_buttons" "$es_swap"

    # enable menu_unified_controls by default (see below for more info)
    iniSet "menu_unified_controls" "true"

    # disable 'press twice to quit'
    iniSet "quit_press_twice" "false"

    # enable video shaders
    iniSet "video_shader_enable" "true"

    # enable overlays by default
    iniSet "input_overlay_enable" "true"

    # disable save paths under sub-folders
    iniSet "sort_savestates_enable" "false"
    iniSet "sort_savefiles_enable" "false"

    copyDefaultConfig "$config" "$configdir/all/retroarch.cfg"
    rm "$config"

    # if no menu_driver is set, force RGUI, as the default has now changed to XMB.
    _set_config_option_retroarch "menu_driver" "rgui"

    # set RGUI aspect ratio to "Integer Scaling" to prevent stretching
    _set_config_option_retroarch "rgui_aspect_ratio_lock" "2"

    # if no menu_unified_controls is set, force it on so that keyboard player 1 can control
    # the RGUI menu which is important for arcade sticks etc that map to keyboard inputs
    _set_config_option_retroarch "menu_unified_controls" "true"

    # disable `quit_press_twice` on existing configs
    _set_config_option_retroarch "quit_press_twice" "false"

    # enable video shaders on existing configs
    _set_config_option_retroarch "video_shader_enable" "true"

    # (compat) keep all core options in a single file
    _set_config_option_retroarch "global_core_options" "true"

    # disable the content load info popup with core and game info
    _set_config_option_retroarch "menu_show_load_content_animation" "false"

    # disable search action
    _set_config_option_retroarch "menu_disable_search_button" "true"

    # don't save input remaps by default
    _set_config_option_retroarch "remap_save_on_exit" "false"

    # enable overlays by default on upgrades
    _set_config_option_retroarch "input_overlay_enable" "true"

    # don't sort save files in sub-folders
    _set_config_option_retroarch "sort_savefiles_enable" "false"
    _set_config_option_retroarch "sort_savestates_enable" "false"

    # remapping hack for old 8bitdo firmware
    addAutoConf "8bitdo_hack" 0
}

function keyboard_retroarch() {
    if [[ ! -f "$configdir/all/retroarch.cfg" ]]; then
        printMsgs "dialog" "No RetroArch configuration file found at $configdir/all/retroarch.cfg"
        return
    fi
    local input
    local options
    local i=1
    local key=()
    while read input; do
        local parts=($input)
        key+=("${parts[0]}")
        options+=("${parts[0]}" $i 2 "${parts[*]:2}" $i 26 16 0)
        ((i++))
    done < <(grep "^[[:space:]]*input_player[0-9]_[a-z]*" "$configdir/all/retroarch.cfg")
    local cmd=(dialog --backtitle "$__backtitle" --form "RetroArch keyboard configuration" 22 48 16)
    local choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    if [[ -n "$choice" ]]; then
        local value
        local values
        readarray -t values <<<"$choice"
        iniConfig " = " '"' "$configdir/all/retroarch.cfg"
        i=0
        for value in "${values[@]}"; do
            iniSet "${key[$i]}" "$value" >/dev/null
            ((i++))
        done
    fi
}

function hotkey_retroarch() {
    iniConfig " = " '"' "$configdir/all/retroarch.cfg"
    local cmd=(dialog --backtitle "$__backtitle" --menu "Choose the desired hotkey behaviour." 22 76 16)
    local options=(1 "Hotkeys enabled. (default)"
             2 "Press ALT to enable hotkeys."
             3 "Hotkeys disabled. Press ESCAPE to open RGUI.")
    local choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    if [[ -n "$choice" ]]; then
        case "$choice" in
            1)
                iniSet "input_enable_hotkey" "nul"
                iniSet "input_exit_emulator" "escape"
                iniSet "input_menu_toggle" "F1"
                ;;
            2)
                iniSet "input_enable_hotkey" "alt"
                iniSet "input_exit_emulator" "escape"
                iniSet "input_menu_toggle" "F1"
                ;;
            3)
                iniSet "input_enable_hotkey" "escape"
                iniSet "input_exit_emulator" "nul"
                iniSet "input_menu_toggle" "escape"
                ;;
        esac
    fi
}

function gui_retroarch() {
    while true; do
        local names=(shaders overlays assets)
        local dirs=(shaders overlay assets)
        local options=()
        local name
        local dir
        local i=1
        for name in "${names[@]}"; do
            if [[ -d "$configdir/all/retroarch/${dirs[i-1]}/.git" ]]; then
                options+=("$i" "Manage $name (installed)")
            else
                options+=("$i" "Manage $name (not installed)")
            fi
            ((i++))
        done
        options+=(
            4 "Configure keyboard for use with RetroArch"
            5 "Configure keyboard hotkey behaviour for RetroArch"
        )
        local cmd=(dialog --backtitle "$__backtitle" --menu "Choose an option" 22 76 16)
        local choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
        case "$choice" in
            1|2|3)
                name="${names[choice-1]}"
                dir="${dirs[choice-1]}"
                options=(1 "Install/Update $name" 2 "Uninstall $name" )
                cmd=(dialog --backtitle "$__backtitle" --menu "Choose an option for $dir" 12 40 06)
                choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)

                case "$choice" in
                    1)
                        "update_${name}_retroarch"
                        ;;
                    2)
                        rm -rf "$configdir/all/retroarch/$dir"
                        [[ "$dir" == "assets" ]] && install_xmb_monochrome_assets_retroarch
                        ;;
                    *)
                        continue
                        ;;

                esac
                ;;
            4)
                keyboard_retroarch
                ;;
            5)
                hotkey_retroarch
                ;;
            *)
                break
                ;;
        esac

    done
}

# adds a retroarch global config option in `$configdir/all/retroarch.cfg`, if not already set
function _set_config_option_retroarch()
{
    local option="$1"
    local value="$2"
    iniConfig " = " '"' "$configdir/all/retroarch.cfg"
    iniGet "$option"
    if [[ -z "$ini_value" ]]; then
        iniSet "$option" "$value"
    fi
}
