const mediaPrefersDarkTheme = window.matchMedia('(prefers-color-scheme: dark)')

function selectTheme(selectedTheme) {
  // Apply and remember the specified theme.
  applyTheme(selectedTheme)
  if ((selectedTheme === 'dark') === mediaPrefersDarkTheme.matches) {
    // Selected theme is the same as the device's preferred theme, so we can forget this setting.
    localStorage.removeItem('theme')
  } else {
    // Remember the selected theme to apply it on the next visit
    localStorage.setItem('theme', selectedTheme)
  }
}

function applyTheme(theme) {
  document.body.classList.toggle('theme-dark', theme === 'dark')
  document.body.classList.toggle('theme-light', theme !== 'dark')
}

// If user had selected a theme, load it. Otherwise, use device's preferred theme
const selectedTheme = localStorage.getItem('theme')
if (selectedTheme) {
  applyTheme(selectedTheme)
} else {
  applyTheme(mediaPrefersDarkTheme.matches ? 'dark' : 'light')
}

// Watch the device's preferred theme and update theme if user did not select a theme
mediaPrefersDarkTheme.addEventListener('change', () => {
  const selectedTheme = localStorage.getItem('theme')
  if (!selectedTheme) {
    applyTheme(mediaPrefersDarkTheme.matches ? 'dark' : 'light')
  }
})


// Add handlers for theme selection buttons.
document.addEventListener('DOMContentLoaded', function () {
  document.querySelector('[data-theme-toggle]').addEventListener('click', () => {
    const theme = document.body.classList.contains('theme-dark') ? 'light' : 'dark'
    selectTheme(theme)
  })
});
