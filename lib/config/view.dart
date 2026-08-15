/// View Configuration.
///
/// Customizes the appearance of Magic UI components (dialogs, confirms,
/// loading). These className values are read by MagicFeedback via
/// `Config.get('view.*')`.
Map<String, dynamic> get viewConfig => {
  'view': {
    // **Every toast in this app rendered in a colour DESIGN.md does not contain**, because nothing
    // set these and `MagicFeedback.showSnackbar` falls back to `bg-gray-900 text-white`. Generic
    // Tailwind grey, on a palette built entirely from Apple's increased-contrast system colours, and
    // `bin/design-tokens` could not see it: the hex is in the framework's default rather than in our
    // code.
    //
    // These are semantic aliases, so each carries its own `dark:` pair and the toast follows the
    // appearance like everything else. `success` is `bg-success` rather than the `in-stock` status
    // family: a saved change is not a stock LEVEL, and borrowing a status family for something it
    // does not name is what DESIGN.md's avoid-list warns about.
    //
    // The pairs are the ones DESIGN.md already guarantees a contrast for. `warning` and `success` are
    // dark fills in light mode and bright ones in dark, which is why both take `text-on-primary`
    // rather than a fixed white: that alias flips with the appearance, and white on `#FFB340` is
    // 1.9:1.
    'snackbar': {
      'style': {
        'success': 'bg-success text-on-primary',
        'error': 'bg-destructive text-on-destructive',
        'warning': 'bg-warning text-on-primary',
        'info': 'bg-primary text-on-primary',
      },
    },
    'dialog': {'class': 'bg-white dark:bg-gray-800 rounded-xl p-6 shadow-2xl max-w-lg'},
    'confirm': {
      'container_class': 'bg-white dark:bg-gray-800 rounded-xl p-6 shadow-2xl w-80',
      'title_class': 'text-lg font-bold text-gray-900 dark:text-white',
      'message_class': 'text-gray-600 dark:text-gray-400 mt-2',
      'button_cancel_class': 'px-4 py-2 text-gray-600 dark:text-gray-300',
      'button_confirm_class': 'px-4 py-2 bg-primary text-white rounded-lg',
      'button_danger_class': 'px-4 py-2 bg-red-500 text-white rounded-lg',
    },
  },
};
