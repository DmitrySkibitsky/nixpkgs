{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  cmake,
  makeWrapper,
  writeShellScript,
  alsa-lib,
  libpulseaudio,
  libGL,
  libx11,
  libxkbcommon,
  wayland,
  libxcursor,
  libxi,
  libxrandr,
  apple-sdk_15,
}:

let
  # projectm-sys expects CMake to install into lib/, while CMake defaults to
  # lib64/ on NixOS. Wrap cmake to force it, matching upstream's flake.nix.
  cmakeWithLibdir = writeShellScript "cmake-fastpotify" ''
    if [[ "$1" == "--build" ]]; then
      exec ${cmake}/bin/cmake "$@"
    else
      exec ${cmake}/bin/cmake "$@" -DCMAKE_INSTALL_LIBDIR=lib
    fi
  '';
in
rustPlatform.buildRustPackage rec {
  pname = "fastpotify";
  version = "0.7.0";

  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "crmne";
    repo = "fastpotify";
    tag = "v${version}";
    hash = "sha256-XZovQINJXG68ex8amJ6Sx9jphs6AIPnhLtI7Wh9TFgA=";
  };

  cargoHash = "sha256-m3mc9NppLyUkKNXv/U0NZOdLUC6CAi7+LUqfsc4/q30=";

  nativeBuildInputs = [
    pkg-config
    cmake
    rustPlatform.bindgenHook
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ makeWrapper ];

  buildInputs =
    lib.optionals stdenv.hostPlatform.isLinux [
      alsa-lib
      libpulseaudio
      libGL
      libx11
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [ apple-sdk_15 ];

  env.CMAKE = "${cmakeWithLibdir}";

  # The GUI dlopens its Wayland, X11 and GL libraries at run time.
  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    wrapProgram $out/bin/fastpotify \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          libxkbcommon
          wayland
          libGL
          libx11
          libxcursor
          libxi
          libxrandr
        ]
      }
  '';

  postInstall = lib.optionalString stdenv.hostPlatform.isLinux ''
    install -Dm644 packaging/applications/fastpotify.desktop \
      $out/share/applications/fastpotify.desktop
    install -Dm644 packaging/icons/fastpotify.svg \
      $out/share/icons/hicolor/scalable/apps/fastpotify.svg
  '';

  meta = {
    description = "Fast native Spotify client with local playback and Spotify Connect";
    homepage = "https://fastpotify.rocks";
    changelog = "https://github.com/crmne/fastpotify/releases/tag/v${version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ DmitrySkibitsky ];
    mainProgram = "fastpotify";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
