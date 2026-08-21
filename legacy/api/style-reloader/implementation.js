"use strict";

/* global ExtensionAPI, Cc, Ci, Services */

this.styleReloader = class extends ExtensionAPI {
  constructor(extension) {
    super(extension);
    this.registeredUri = null;
    this.styleSheetService = Cc[
      "@mozilla.org/content/style-sheet-service;1"
    ].getService(Ci.nsIStyleSheetService);
  }

  unregisterCurrentSheet() {
    if (
      this.registeredUri &&
      this.styleSheetService.sheetRegistered(
        this.registeredUri,
        this.styleSheetService.AUTHOR_SHEET
      )
    ) {
      this.styleSheetService.unregisterSheet(
        this.registeredUri,
        this.styleSheetService.AUTHOR_SHEET
      );
    }

    this.registeredUri = null;
  }

  getAPI() {
    return {
      styleReloader: {
        replace: async css => {
          if (typeof css !== "string" || css.trim() === "") {
            throw new Error("Stylesheet content must be a non-empty string");
          }

          const uri = Services.io.newURI(
            `data:text/css;charset=utf-8,${encodeURIComponent(css)}`
          );

          this.unregisterCurrentSheet();
          this.styleSheetService.loadAndRegisterSheet(
            uri,
            this.styleSheetService.AUTHOR_SHEET
          );
          this.registeredUri = uri;
        },
      },
    };
  }

  onShutdown() {
    this.unregisterCurrentSheet();
  }
};
