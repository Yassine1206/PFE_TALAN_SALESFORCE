import getThemePreference from "@salesforce/apex/CkThemeController.getThemePreference";

export function applyThemeToComponent(cmp) {
  getThemePreference()
    .then((theme) => {
      if (theme === "Dark") {
        cmp.setAttribute("data-theme", "dark");
      } else {
        cmp.removeAttribute("data-theme");
      }
    })
    .catch((error) => {
      // eslint-disable-next-line no-console
      console.error("Theme load error:", error);
    });
}
