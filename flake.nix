{
  description = "Claude Usage Monitor - Display Claude Pro/Max subscription usage in statuslines and bars";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;

          # Wrap script with PATH containing dependencies
          wrapScript = name: src: pkgs.stdenv.mkDerivation {
            inherit name;
            dontUnpack = true;
            nativeBuildInputs = [ pkgs.makeWrapper ];
            installPhase = ''
              mkdir -p $out/bin
              cp ${src} $out/bin/${name}
              chmod +x $out/bin/${name}
              wrapProgram $out/bin/${name} \
                --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.curl pkgs.jq pkgs.coreutils ]}
            '';
          };
        in
        {
          claude-usage-statusline = wrapScript "claude-usage-statusline" ./claude-usage-statusline.sh;
          claude-usage-bar = wrapScript "claude-usage-bar" ./claude-usage-bar.sh;
          claude-usage-cycle = wrapScript "claude-usage-cycle" ./claude-usage-cycle.sh;
          claude-model-check = wrapScript "claude-model-check" ./claude-model-check.sh;

          default = pkgs.symlinkJoin {
            name = "claude-usage-monitor";
            paths = [
              self.packages.${system}.claude-usage-statusline
              self.packages.${system}.claude-usage-bar
              self.packages.${system}.claude-usage-cycle
              self.packages.${system}.claude-model-check
            ];
          };
        }
      );

      # Home Manager module
      homeManagerModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.programs.claude-usage-monitor;
        in
        {
          options.programs.claude-usage-monitor = {
            enable = lib.mkEnableOption "Claude Usage Monitor";

            statusline = {
              enable = lib.mkEnableOption "Claude Code statusline integration";
              barWidth = lib.mkOption {
                type = lib.types.int;
                default = 30;
                description = "Width of progress bars in statusline";
              };
            };

            bar = {
              enable = lib.mkEnableOption "Status bar integration (waybar, hyprpanel, etc.)";
              barWidth = lib.mkOption {
                type = lib.types.int;
                default = 8;
                description = "Width of progress bars in bar module";
              };
            };
          };

          config = lib.mkIf cfg.enable {
            home.packages = [
              self.packages.${pkgs.system}.default
            ];
          };
        };

      # Overlay for use in other flakes
      overlays.default = final: prev: {
        claude-usage-monitor = self.packages.${prev.system}.default;
        claude-usage-statusline = self.packages.${prev.system}.claude-usage-statusline;
        claude-usage-bar = self.packages.${prev.system}.claude-usage-bar;
        claude-usage-cycle = self.packages.${prev.system}.claude-usage-cycle;
        claude-model-check = self.packages.${prev.system}.claude-model-check;
      };
    };
}
