{ pkgs, ... }:
{
  home.packages = with pkgs; [
    waybar
    kitty
    wlogout
    wofi
    hyprpaper
    hyprshot
    hyprlock
    hypridle
    hyprsunset
    hyprlauncher
    hyprtoolkit
    wl-clipboard
    brightnessctl
    swaynotificationcenter
    libnotify
    networkmanagerapplet
    pulseaudio
    fastfetch
    jp2a
    vscode
    code-cursor-fhs
    spotify
    obsidian
    telegram-desktop

    adwaita-icon-theme
    hicolor-icon-theme
    gnome-tweaks
    cheese

    pwvucontrol
    easyeffects

    gnome-disk-utility
    showtime
    nautilus
    loupe
    gnome-settings-daemon

    overskride
    cava

    cmatrix
    sl
    bun
    python313Packages.pygobject3
    gtk4
    gtk3
    libadwaita

    gcc
    antigravity

    obs-studio
  ];
}
