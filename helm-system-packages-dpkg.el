;;; helm-system-packages-dpkg.el --- Helm UI for Debian's dpkg. -*- lexical-binding: t -*-

;; Copyright (C) 2012 ~ 2014 Thierry Volpiatto <thierry.volpiatto@gmail.com>
;;               2017        Pierre Neidhardt <ambrevar@gmail.com>

;; Author: Pierre Neidhardt <ambrevar@gmail.com>
;; URL: https://github.com/emacs-helm/helm-system-packages
;; Version: 1.6.9
;; Package-Requires: ((emacs "24.4") (helm "2.8.6"))
;; Keywords: helm, packages

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;; Helm UI for dpkg.

;;; Code:
(require 'helm)
(require 'helm-system-packages)

(defun helm-system-packages-dpkg-list-explicit ()
  "List explicitly installed packages."
  (split-string (with-temp-buffer
                  (call-process "apt-mark" nil t nil "showmanual")
                  (buffer-string))))

(defun helm-system-packages-dpkg-list-dependencies ()
  "List packages installed as a dependency."
  (split-string (with-temp-buffer
                  (call-process "apt-mark" nil t nil "showauto")
                  (buffer-string))))

(defun helm-system-packages-dpkg-list-all ()
  "List all packages."
  (sort
   (split-string (with-temp-buffer
                   (call-process "apt-cache" nil t nil "pkgnames")
                   (buffer-string)))
   'string<))

(defun helm-system-packages-dpkg-list-descriptions ()
  "Cache all package descriptions."
  (with-temp-buffer
    ;; `apt-cache search` is much faster than `apt-cache show`.
    (call-process "apt-cache" nil '(t nil) nil "search" ".")
    (let (descs)
      (goto-char (point-min))
      (while (re-search-forward "^\\(.*\\) \\- \\(.*\\)" nil t)
        (push (cons (intern (match-string 1)) (match-string 2)) descs))
      descs)))

(defun helm-system-packages-dpkg-print-url (_)
  "Print homepage URLs of `helm-marked-candidates'.

With prefix argument, insert the output at point.
Otherwise display in `helm-system-packages-buffer'."
  (let ((res (helm-system-packages-run "apt-cache" "show"))
        urls)
    (dolist (url (split-string res "\n" t))
      (when (string-match "^Homepage: \\(.*\\)" url)
        (push (match-string 1 url) urls)))
    (helm-system-packages-browse-url urls)))

(defvar helm-system-packages-dpkg-source
  (helm-build-in-buffer-source "dpkg source"
    :init 'helm-system-packages-init
    :candidate-transformer 'helm-system-packages-highlight
    :candidate-number-limit helm-system-packages-candidate-limit
    :action '(("Show package(s)" .
               (lambda (_)
                 (helm-system-packages-print "apt-cache" "show")))
              ("Install (`C-u' to reinstall)" .
               (lambda (_)
                 (helm-system-packages-run-as-root "apt-get" "install" (when helm-current-prefix-arg "--reinstall") )))
              ("Uninstall (`C-u' to include dependencies)" .
               (lambda (_)
                 (helm-system-packages-run-as-root "apt-get" "remove" (when helm-current-prefix-arg "--auto-remove"))))
              ("Find files" .
               (lambda (_)
                 (helm-system-packages-find-files "dpkg" "--listfiles")))
              ("Show dependencies" .
               (lambda (_)
                 (helm-system-packages-print "apt-cache" "depends")))
              ("Show reverse dependencies" .
               (lambda (_)
                 (helm-system-packages-print "apt-cache" "rdepends")))
              ("Browse homepage URL" . helm-system-packages-dpkg-print-url)
              ("Uninstall/Purge (`C-u' to include dependencies)" .
               (lambda (_)
                 (helm-system-packages-run-as-root "apt-get" "purge" (when helm-current-prefix-arg "--auto-remove")))))))

;; TODO: Factor into entry function?
(defun helm-system-packages-dpkg ()
  "Preconfigured `helm' for dpkg."
  (helm :sources '(helm-system-packages-dpkg-source)
        :buffer "*helm dpkg*"
        :truncate-lines t
        :input (substring-no-properties (or (thing-at-point 'symbol) ""))))

(provide 'helm-system-packages-dpkg)

;;; helm-system-packages-dpkg.el ends here
