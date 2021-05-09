# `grab-mac-link.el`

Grab link from Mac Apps.

## Supported Apps

- Chrome
- Safari
- Firefox
- Vivaldi
- Finder
- Mail
- Terminal
- [Skim](http://skim-app.sourceforge.net/)

## Supported Link types

    Plain:    https://www.wikipedia.org/
    Markdown: [Wikipedia](https://www.wikipedia.org/)
    Org:      [[https://www.wikipedia.org/][Wikipedia]]
    HTML:     <a href="https://www.wikipedia.org/">Wikipedia</a>

## Usage

### `M-x grab-mac-link`

Prompt for an application to grab a link from and prompt for a link
type to insert as, then insert it at point. With one universal
argument, copies the link instead of inserting it. With two universal
arguments, uses the default app and link-type instead of prompting.

### Customization

Set `grab-mac-link-preferred-app` to the name of the app to use.

``` emacs-lisp
(setq grab-mac-link-preferred-app "firefox")
```

Set `grab-mac-link-preferred-link-type` to the name of the link-type,
eg, "org". Choose an application according to
`grab-mac-link-dwim-favourite-app` and link type according to the
current buffer's major mode, i.e., `major-mode`.

``` emacs-lisp
;; no preferred type, will prompt
(setq grab-mac-link-preferred-link-type nil)

;; prefer org-mode style
(setq grab-mac-link-preferred-link-type "org")

;; guess the preferred type from the current buffer's mode
(setq grab-mac-link-preferred-link-type 'from-mode)
```

Remove an app from the menu.
```emacs-lisp
(setq gml--app-alist (cl-remove "mail" gml--app-alist
                                :test #'string-equal :key #'car))
```

## Acknowledgment

AppleScript code used in this program is borrowed from
[`org-mac-link.el`](http://orgmode.org/worg/org-contrib/org-mac-link.html).

This is a fork of [xuchunyang/grab-mac-link.el: Grab link from Mac
Apps and insert it into
Emacs](https://github.com/xuchunyang/grab-mac-link.el), although I've
changed so much of the code that it is less of a fork, and more an
entirely new set of silverware. Many functions and variable names have
changed, so it is not backward compatible.
