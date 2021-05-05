;;; grab-mac-link.el --- Grab link from Mac Apps and insert it into Emacs  -*- lexical-binding: t; -*-

;; Copyright (c) 2010-2016 Free Software Foundation, Inc.
;; Copyright (C) 2016-2020 Xu Chunyang

;; The code is heavily inspired by org-mac-link.el

;; Authors of org-mac-link.el:
;;      Anthony Lander <anthony.lander@gmail.com>
;;      John Wiegley <johnw@gnu.org>
;;      Christopher Suckling <suckling at gmail dot com>
;;      Daniil Frumin <difrumin@gmail.com>
;;      Alan Schmitt <alan.schmitt@polytechnique.org>
;;      Mike McLean <mike.mclean@pobox.com>

;; Author: Xu Chunyang
;; URL: https://github.com/xuchunyang/grab-mac-link.el
;; Version: 0.3
;; Package-Requires: ((emacs "24"))
;; Keywords: mac, hyperlink
;; Created: Sat Jun 11 15:07:18 CST 2016

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Grabs a URL from a Mac application, and insert in current buffer,
;; or store on kill ring (or org-stored-links).

;; The following applications are supported:
;; - Chrome
;; - Safari
;; - Firefox
;; - Vivaldi
;; - Finder
;; - Mail
;; - Terminal
;; - Skim
;;
;; The following link types are supported:
;; - plain:    https://www.wikipedia.org/
;; - markdown: [Wikipedia](https://www.wikipedia.org/)
;; - org:      [[https://www.wikipedia.org/][Wikipedia]]
;; - html:     <a href="https://www.wikipedia.org/">Wikipedia</a>
;;
;; To use, type M-x grab-mac-link
;;
;;   (grab-mac-link APP)
;;

;;; Code:

(require 's)
(require 'cl-lib)
(require 'org)

(declare-function org-add-link-type "org-compat" (type &optional follow export))
(declare-function org-link-make-string "ol" (link &optional description))

(defvar org-stored-links)

(defun gml--split (as-link)
  (split-string as-link "::split::"))

(defun gml--unquote (s)
  (if (string-prefix-p "\"" s)
      (substring s 1 -1)
    s))

(defun gml--make-plain-link (url _name)
  url)

;; Handle links from Skim.app
;;
;; Original code & idea by Christopher Suckling (org-mac-protocol)

(org-add-link-type "skim" 'org-mac-skim-open)

(defun org-mac-skim-open (uri)
  "Visit page of pdf in Skim"
  (let* ((page (when (string-match "::\\(.+\\)\\'" uri)
                 (match-string 1 uri)))
         (document (substring uri 0 (match-beginning 0))))
    (do-applescript
     (concat
      "tell application \"Skim\"\n"
      "activate\n"
      "set theDoc to \"" document "\"\n"
      "set thePage to " page "\n"
      "open theDoc\n"
      "go document 1 to page thePage of document 1\n"
      "end tell"))))

;; Handle links from Mail.app

(org-add-link-type "message" 'org-mac-message-open)

(defun org-mac-message-open (message-id)
  "Visit the message with MESSAGE-ID.
This will use the command `open' with the message URL."
  (start-process (concat "open message:" message-id) nil
                 "open" (concat "message://<" (substring message-id 2) ">")))

(defun gml--make-org-link (url name)
  "Make an org-mode compatible link."
  ;; avoid putting a description item with a double colon in an org
  ;; link. Doing so makes the link inactive.
  (org-link-make-string url (s-replace "::" ":" name)))

(defun gml--make-markdown-link (url name)
  "Make a Markdown inline link."
  (format "[%s](%s)" name url))

(defun gml--make-html-link (url name)
  "Make an HTML <a> link."
  (format "<a href=\"%s\">%s</a>" url name))


;; Google Chrome.app

(defun gml--chrome-handler ()
  (let ((raw-link
         (do-applescript
          (concat
           "set frontmostApplication to path to frontmost application\n"
           "tell application \"Google Chrome\"\n"
           "	set theUrl to get URL of active tab of first window\n"
           "	set theTitle to get title of active tab of first window\n"
           "	set theResult to (get theUrl) & \"::split::\" & theTitle\n"
           "end tell\n"
           "activate application (frontmostApplication as text)\n"
           "set links to {}\n"
           "copy theResult to the end of links\n"
           "return links as string\n"))))
    (gml--split
     (replace-regexp-in-string
      "^\"\\|\"$" "" (car (split-string raw-link "[\r\n]+" t))))))


;; Vivaldi.app

;; very similar to the one from Chrome
(defun gml--vivaldi-handler ()
  (let ((raw-link
         (condition-case nil
	 (do-applescript
	  (concat
	   "set frontmostApplication to path to frontmost application\n"
	   "tell application \"Vivaldi\"\n"
	   "	set theUrl to get URL of active tab of first window\n"
	   "	set theResult to (get theUrl) & \"::split::\" & (get name of window 1)\n"
	   "end tell\n"
	   "activate application (frontmostApplication as text)\n"
	   "set links to {}\n"
	   "copy theResult to the end of links\n"
	   "return links as string\n"))
         ;; if there is an applescript error (because there is no
         ;; window), then return nil
         (error nil))))
    (if raw-link
        (gml--split (car (split-string raw-link "[\r\n]+" t)))
      nil)))


;; Firefox.app

(defvar gml--firefox-app-name "Firefox"
  "Name of the firefox app, eg, \"Firefox\" or \"Firefox Nightly\".")

(defun gml--firefox-handler ()
  (let* ((raw-link
          (do-applescript
           (concat
            "set oldClipboard to the clipboard\n"
            ;; clear out the clipboard in case there is nothing for
            ;; firefox to return
            "set the clipboard to \"\"\n"
            "set frontmostApplication to path to frontmost application\n"
            "tell application \"" gml--firefox-app-name "\"\n"
            "	activate\n"
            "	delay 0.15\n"
            "	tell application \"System Events\"\n"
            "		keystroke \"l\" using {command down}\n"
            "		keystroke \"a\" using {command down}\n"
            "		keystroke \"c\" using {command down}\n"
            "	end tell\n"
            "	delay 0.15\n"
            "	set theUrl to the clipboard\n"
            "	set the clipboard to oldClipboard\n"
            "	set theResult to (get theUrl) & \"::split::\" & (get name of window 1)\n"
            "end tell\n"
            "activate application (frontmostApplication as text)\n"
            "set links to {}\n"
            "copy theResult to the end of links\n"
            "return links as string\n")))
         (link-list (gml--split (car (split-string raw-link "[\r\n]+" t)))))
        (if (string-equal "" (car link-list))
            nil
          link-list)))


;; Safari.app

(defun gml--safari-handler ()
  (let ((raw-link (do-applescript
                   (concat
                    "tell application \"Safari\"\n"
                    "	set theUrl to URL of document 1\n"
                    "	set theName to the name of the document 1\n"
                    "	return theUrl & \"::split::\" & theName\n"
                    "end tell\n"))))
    (if (stringp raw-link)
        (gml--split (gml--unquote raw-link))
      nil)))


;; Finder.app

(defun gml--finder-selected-items ()
  (split-string
   (do-applescript
    (concat
     "tell application \"Finder\"\n"
     " set theSelection to the selection\n"
     " set links to {}\n"
     " repeat with theItem in theSelection\n"
     " set theLink to \"file://\" & (POSIX path of (theItem as string)) & \"::split::\" & (get the name of theItem) & \"\n\"\n"
     " copy theLink to the end of links\n"
     " end repeat\n"
     " return links as string\n"
     "end tell\n"))
   "\n" t))

(defun gml--finder-handler ()
  "Return selected file in Finder.
If there are more than one selected files, just return the first one.
If there are none, return nil."
  (car (mapcar #'gml--split (gml--finder-selected-items))))


;; Mail.app

(defun gml--mail-handler ()
  "AppleScript to create links to selected messages in Mail.app."
  (gml--split
   (do-applescript
    (concat
     "tell application \"Mail\"\n"
     "set theLinkList to {}\n"
     "set theSelection to selection\n"
     "repeat with theMessage in theSelection\n"
     "set theID to message id of theMessage\n"
     "set theSubject to subject of theMessage\n"
     "set theLink to \"message://<\" & theID & \">::split::\" & theSubject\n"
     "if (theLinkList is not equal to {}) then\n"
     "set theLink to \"\n\" & theLink\n"
     "end if\n"
     "copy theLink to end of theLinkList\n"
     "end repeat\n"
     "return theLinkList as string\n"
     "end tell"))))


;; Terminal.app

(defun gml--terminal-handler ()
  (gml--split
   (gml--unquote
    (do-applescript
     (concat
      "tell application \"Terminal\"\n"
      "  set theName to custom title in tab 1 of window 1\n"
      "  do script \"pwd | pbcopy\" in window 1\n"
      "  set theUrl to do shell script \"pbpaste\"\n"
      "  return theUrl & \"::split::\" & theName\n"
      "end tell")))))


;; Skim.app
(defun gml--skim-handler ()
  (gml--split
   (do-applescript
    (concat
     "tell application \"Skim\"\n"
     "set theDoc to front document\n"
     "set theTitle to (name of theDoc)\n"
     "set thePath to (path of theDoc)\n"
     "set thePage to (get index for current page of theDoc)\n"
     "set theSelection to selection of theDoc\n"
     "set theContent to contents of (get text for theSelection)\n"
     "if theContent is missing value then\n"
     "    set theContent to theTitle & \", p. \" & thePage\n"
     "end if\n"
     "set theLink to \"skim://\" & thePath & \"::\" & thePage & "
     "\"::split::\" & theContent\n"
     "end tell\n"
     "return theLink as string\n"))))


;; One Entry point for all

(defvar gml--app-alist
  '(("chrome" . gml--chrome-handler)
    ("safari" . gml--safari-handler)
    ("firefox" . gml--firefox-handler)
    ("vivaldi" . gml--vivaldi-handler)
    ("Finder" . gml--finder-handler)
    ("mail" . gml--mail-handler)
    ("terminal" . gml--terminal-handler)
    ("Skim" . gml--skim-handler))
  "Alist of (app-name . app-fn). First char of app-name is used
for the menu.")

(defvar gml--link-types-alist
  '(("plain" . gml--make-plain-link)
    ("markdown" . gml--make-markdown-link)
    ("org" . gml--make-org-link)
    ("html" . gml--make-html-link))
  "Alist of (link-type-name . link-fn). First char of
link-type-name is used for the menu.")

(defvar gml--link-type-mode-alist
  '((markdown-mode . "markdown")
    (org-mode . "org")
    (html-mode . "html"))
  "Alist of (mode-symbol . link-type-name)")

(defface gml-dispatcher-highlight
  '((t :background "gold1"))
  "The background color used to highlight the dispatch character.")

(defun gml--create-menu-string (alist)
  "Build the menu string from ALIST. First char of name is used
for dispatching, and is marked with brackets and a different
face."
  (cl-loop for (app-string . fn) in alist
           collect (concat " ["
                           (propertize (substring app-string 0 1) 'face 'gml-dispatcher-highlight)
                           "]"
                           (substring app-string 1))
           into s-list
           finally (return (apply #'concat s-list))))

(defun gml--assoc-first-char (char alist)
  "Like assoc, but match on CHAR and first character of the car of
each pair in ALIST"
  (let ((case-fold-search nil))
    (cl-assoc-if (lambda (s) (char-equal char (aref s 0))) alist)))

(defvar grab-mac-link-preferred-app nil
  "Preferred app to use when `grab-mac-link' is called with two
prefix arguments. Should be a string, such as \"firefox\", that
appears in `gml--app-alist")

(defvar grab-mac-link-preferred-link-type nil
  "Preferred link type to use when `grab-mac-link' is called with
two prefix arguments. Can be a string, such as \"org\", nil for
no default, or 'from-mode to guess from the current buffer mode.")

;;;###autoload
(defun grab-mac-link (arg)
  "Prompt for an application to grab a link from.
When done, go grab the link, and insert it at point.

With single prefix argument, instead of \"insert\", save link to
kill-ring. For an org link, save it to `org-stored-links' so you
insert it with `org-insert-link'.

With two prefix arguments, use the default app name in
`grab-mac-link-preferred--app' and guess the link type from the
current buffer's mode as per
`grab-mac-link-preferred-link-type'."
  (interactive "p")
  (let* ((app-name (if (= arg 16)
                       grab-mac-link-dwim-favourite-app
                     (let* ((app-menu (format "Grab link from%s"
                                              (gml--create-menu-string gml--app-alist)))
                            (input1 (read-char-exclusive app-menu)))
                       (or (car (gml--assoc-first-char input1 gml--app-alist))
                           (error (format "%s is not a valid input" (char-to-string input1)))))))
         (link-type (if (= arg 16)
                        (if (eq grab-mac-link-preferred-link-type 'from-mode)
                          (cl-loop for (mode-symbol . link-type-name) in gml--link-type-mode-alist
                                   when (derived-mode-p mode-symbol)
                                   return link-type-name
                                   finally (return "plain"))
                          (or grab-mac-link-preferred-link-type
                              "plain"))
                      (let* ((link-type-menu (format "Grab link from %s as a%s link:"
                                                     app-name
                                                     (gml--create-menu-string gml--link-types-alist)))
                             (input2 (read-char-exclusive link-type-menu)))
                        (or (car (gml--assoc-first-char input2 gml--link-types-alist))
                            ;; if not specified (or incorrectly specified), then use plain
                            "plain"))))
         (grab-link-fn (cdr (gml--assoc-first-char (aref app-name 0) gml--app-alist)))
         (make-link-fn (cdr (gml--assoc-first-char (aref link-type 0) gml--link-types-alist)))
         (raw-link (funcall grab-link-fn))
         (link (if raw-link
                   (apply make-link-fn raw-link)
                 (error "Nothing to link to found in app %s" app-name))))
    (if (= arg 4)
        (if (string-equal link-type "org")
            (let* ((res raw-link)
                   (link (car res))
                   (desc (cadr res)))
              ;; for org-mode, store in org's var
              (push (list link desc) org-stored-links)
              (message "Stored: %s" desc))
          ;; not org mode, so put on kill ring
          (kill-new link)
          (message "Copied: %s" link))
      ;; not arg 4, so insert in current buffer
      (insert link))
    link))

(provide 'grab-mac-link)
;;; grab-mac-link.el ends here
