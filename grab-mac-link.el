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
;; - Floorp
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
  ;; split at marker and remove "'s
  (split-string as-link "::split::" t "\""))

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

;; make links

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
            "	delay 0.10\n"
            "	tell application \"System Events\"\n"
            "		keystroke \"l\" using {command down}\n"
            "		keystroke \"a\" using {control down}\n"
            "		keystroke \"a\" using {command down}\n"
            "		keystroke \"c\" using {command down}\n"
            "		keystroke \"e\" using {control down}\n"
            "	end tell\n"
            "	delay 0.10\n"
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


;; Floorp.app

(defun gml--floorp-handler ()
  (let* ((raw-link
          (do-applescript
           (concat
            "set oldClipboard to the clipboard\n"
            ;; clear out the clipboard in case there is nothing for
            ;; floorp to return
            "set the clipboard to \"\"\n"
            "set frontmostApplication to path to frontmost application\n"
            "tell application \"Floorp\"\n"
            "	activate\n"
            "	delay 0.06\n"
            "	tell application \"System Events\"\n"
            "		keystroke \"l\" using {command down}\n"
            "		keystroke \"a\" using {command down}\n"
            "		keystroke \"c\" using {command down}\n"
            "	end tell\n"
            "	delay 0.06\n"
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
  "Return selected file(s) in Finder.
If there are none, return nil."
  (mapcar #'gml--split (gml--finder-selected-items)))


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
  '((?c "chrome"   gml--chrome-handler)
    (?s "safari"   gml--safari-handler)
    (?f "firefox"  gml--firefox-handler)
    (?p "floorp"   gml--floorp-handler)
    (?v "vivaldi"  gml--vivaldi-handler)
    (?F "finder"   gml--finder-handler)
    (?m "mail"     gml--mail-handler)
    (?t "terminal" gml--terminal-handler)
    (?S "skim"     gml--skim-handler))
  "Alist of (app-char app-name app-handler-fn).")

(defvar gml--link-types-alist
  '((?p "plain"    gml--make-plain-link)
    (?m "markdown" gml--make-markdown-link)
    (?o "org"      gml--make-org-link)
    (?h "html"     gml--make-html-link))
  "Alist of (link-type-char link-type-name link-fn).")

(defvar gml--link-type-mode-alist
  '((markdown-mode . "markdown")
    (org-mode . "org")
    (html-mode . "html"))
  "Alist of (mode-symbol . link-type-name)")

(defface gml-dispatcher-highlight
  '((t :background "gold1"))
  "The background color used to highlight the dispatch character.")

(defun gml--create-menu-string (alist)
  "Build the menu string from ALIST. The app-char is used
for dispatching, and is marked with brackets and a different
face."
  (cl-loop for (app-char app-string app-fn) in alist
           collect (concat " ["
                           (propertize (string app-char) 'face 'gml-dispatcher-highlight)
                           "]"
                           app-string)
           into s-list
           finally (return (apply #'concat s-list))))

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
When done, grab the link(s), and insert at point."
  (interactive "p")
  (let* ((app-menu (format "Grab link from%s"
                           (gml--create-menu-string gml--app-alist)))
         ;; input1 is a character
         (input1 (read-char-exclusive app-menu))
         ;; app-entry is (<char> <string> <handler>)
         (app-entry (or (assoc input1 gml--app-alist)
                        (error (format "%s is not a valid input" (string input1)))))
         ;; app-name is <string>
         (app-name (cadr app-entry))
         (link-type-menu (format "Grab link from %s as a%s link:"
                                 app-name
                                 (gml--create-menu-string gml--link-types-alist)))
         (input2 (read-char-exclusive link-type-menu))
         ;; grab-link-fn is the handler to get the link info from that app
         (grab-link-fn (caddr app-entry))
         ;; link-entry is (<char> <format> <link-fn>)
         (link-entry (assoc input2 gml--link-types-alist))
         ;; link-type is string, naming the desired type to return
         (link-type (or (cadr link-entry)
                        ;; if not specified (or incorrectly specified), then use plain
                        "plain"))
         (make-link-fn (caddr link-entry))
         ;; get the info from the app
         (raw-link (funcall grab-link-fn)))
    (when (null raw-link)
      (error "Nothing to link to found in app %s" app-name))
    ;; finder returns list of links, others do not
    (unless (string= app-name "finder")
      (setq raw-link (list raw-link)))
    (cl-loop with multiple? = (not (null (cdr raw-link)))
             for rl in raw-link
             for link = (apply make-link-fn rl)
             do (insert link) (when multiple? (insert "\n")))))

(provide 'grab-mac-link)
;;; grab-mac-link.el ends here
