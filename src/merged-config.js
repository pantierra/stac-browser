import defaultConfig from "../config.js";
import externalConfig from "@stac-browser-external-config";

const config = Object.assign(
  {},
  defaultConfig,
  externalConfig,
  CONFIG_FROM_ENV,
  window.STAC_BROWSER_CONFIG
);

if (typeof config.buildTileUrlTemplate === "string") {
  const template = config.buildTileUrlTemplate;
  config.buildTileUrlTemplate = (asset) => template
    .replace(/\{assetUrl\}/g, () => encodeURIComponent(asset.getAbsoluteUrl() ?? asset.href ?? ""))
    .replace(/\{assetHref\}/g, () => asset.href ?? "");
}

export default config;
