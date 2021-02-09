// code /Users/predbjorn/.finicky.js
module.exports = {
  defaultBrowser: "Safari",
  options: {
    // Hide the finicky icon from the top bar. Default: false
    hideIcon: false,
    // Check for update on startup. Default: true
    checkForUpdate: true,
  },
  handlers: [
    {
      match: /^https?:\/\/meet\.google\.com\/.*$/,
      browser: "Google Chrome",
    },
    {
      match: /^https?:\/\/plus\.google\.com\/.*$/,
      browser: "Google Chrome",
    },
    {
      match: /^https?:\/\/datastudio\.google\.com\/.*$/,
      browser: "Google Chrome",
    },
    {
      match: /^https?:\/\/xd\.adobe\.com\/.*$/,
      browser: "Google Chrome",
    },
    {
      match: /^https?:\/\/cms\.helseoversikt\.no\/.*$/,
      browser: "Firefox",
    },
    {
      match: /^https?:\/\/stage\-cms\.helseoversikt\.no\/.*$/,
      browser: "Firefox",
    },
    {
      match: finicky.matchHostnames("localhost"),
      browser: "Firefox",
    },
  ],
};
// match: finicky.matchHostnames('meet.google.com'),
