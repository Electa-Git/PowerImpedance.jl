
(function () {
    const theme = "documenter-dark";

    // Apply the theme before the page renders
    if (localStorage.getItem("documenter-theme") !== theme) {
        localStorage.setItem("documenter-theme", theme);
    }

    // Enforce the theme immediately on page load
    document.documentElement.setAttribute("data-theme", theme);
})();
