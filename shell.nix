{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  VULKAN_INCLUDE_PATH = "${pkgs.lib.makeIncludePath [pkgs.vulkan-headers]}";
  VK_LAYER_PATH = "${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d";
  LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath [pkgs.vulkan-loader]}";
  MESA_SHADER_CACHE_DIR = "${builtins.getEnv "PWD"}/shader_cache";

  buildInputs = with pkgs; [
    vulkan-tools
  ];
}
