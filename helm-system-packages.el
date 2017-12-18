;;; helm-system-packages.el --- Helm UI wrapper for system package managers. -*- lexical-binding: t -*-

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
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;; Helm UI wrapper for system package managers.

;;; Code:
(require 'helm-files)

(defvar helm-system-packages-eshell-buffer "*helm-system-packages-eshell*")
(defvar helm-system-packages-buffer "*helm-system-packages-output*")

(defvar helm-system-packages--all nil
  "String of all packages.")

;; TODO: Split into two functions?
(defvar helm-system-packages-refresh nil
  "Function to refresh the manager state.
It is called:
- On each session start if helm-system-packages--all is nil.
- Whenever a shell command completes.
This must set `helm-system-packages--all' if nil.")

(defvar helm-system-packages--display-lists nil
  "List of ((packages...) . face).

Example:
TODO: Add example.")

(defface helm-system-packages-explicit '((t (:foreground "orange" :weight bold)))
  "Face for excplitly installed packages."
  :group 'helm-system-packages)

(defface helm-system-packages-dependencies '((t (:foreground "lightblue" :slant italic)))
  "Face for packages installed as dependencies."
  :group 'helm-system-packages)

(defgroup helm-system-packages nil
  "Predefined configurations for `helm-system-packages'."
  :group 'helm)

;; TODO: Add "C-]" to local map to toggle details.
(defcustom helm-system-packages-details-flag t
  "Always show details in package list when non-nil."
  :group 'helm-system-packages
  :type 'boolean)

(defcustom helm-system-packages-max-length 36 ; Seems to be a decent value for Portage.
  "Width of the package name column when displaying details."
  :group 'helm-system-packages
  :type 'integerp)

(defcustom helm-system-packages-candidate-limit 1000
  "Maximum number of candidates to display at once.

0 means display all."
  :group 'helm-system-packages
  :type 'integerp)

;; TODO: Rename "highlight" to something else.  "display"?
;; TODO: Propertize the cache directly.
(defun helm-system-packages-highlight (packages)
  "Display PACKAGES using the content of `helm-system-packages--display-lists'."
  (let (res)
    (dolist (pkg packages res)
      (let ((helm-system-packages--display-lists helm-system-packages--display-lists))
        (while (and helm-system-packages--display-lists
                    (not (member (car (split-string pkg)) (caar helm-system-packages--display-lists))))
          (setq helm-system-packages--display-lists (cdr helm-system-packages--display-lists)))
        ;; (message "HELM %S, %S" pkg (length helm-system-packages--display-lists))
        (when helm-system-packages--display-lists
          (push (propertize pkg 'face (cdar helm-system-packages--display-lists)) res))))))

(defun helm-system-packages-run (command &rest args)
  "COMMAND to run over `helm-marked-candidates'."
  (let ((arg-list (append args (helm-marked-candidates))))
    (with-temp-buffer
      ;; We discard errors.
      (apply #'call-process command nil t nil arg-list)
      (buffer-string))))

(defun helm-system-packages-print (command &rest args)
  "COMMAND to run over `helm-marked-candidates'.

With prefix argument, insert the output at point.
Otherwise display in `helm-system-packages-buffer'."
  (let ((res (apply #'helm-system-packages-run command args)))
    (if (string-empty-p res)
        (message "No result")
      (unless helm-current-prefix-arg
        (switch-to-buffer helm-system-packages-buffer)
        (erase-buffer)
        (org-mode)
        ;; TODO: This si too fragile and does not work for pacman.
        ;; Alternative: Simply replace the double linebreak with "* pkg".
        (setq res (replace-regexp-in-string "\\`.*: " "* " res))
        (setq res (replace-regexp-in-string "\n\n.*: " "\n* " res)))
      (insert res))))

(defun helm-system-packages-find-files (command &rest args)
  (let ((res (apply #'helm-system-packages-run command args)))
    (if (string-empty-p res)
        (message "No result")
      (if helm-current-prefix-arg
          (insert res)
        (helm :sources (helm-build-sync-source "Package files"
                         :candidates (split-string res "\n")
                         :candidate-transformer (lambda (files)
                                                  (let ((helm-ff-transformer-show-only-basename nil))
                                                    (mapcar 'helm-ff-filter-candidate-one-by-one files)))
                         :candidate-number-limit 'helm-ff-candidate-number-limit
                         :persistent-action 'helm-find-files-persistent-action
                         :keymap 'helm-find-files-map
                         :action 'helm-find-files-actions)
              :buffer "*helm system package files*")))))

(defun helm-system-packages-run-as-root (command &rest args)
  "COMMAND to run over `helm-marked-candidates'.

COMMAND will be run in an Eshell buffer `helm-system-packages-eshell-buffer'."
  (let ((arg-list (append args (helm-marked-candidates)))
        (eshell-buffer-name helm-system-packages-eshell-buffer))
    ;; Refresh package list after command has completed.
    (push command arg-list)
    (push "sudo" arg-list)
    (eshell)
    (if (eshell-interactive-process)
        (message "A process is already running")
      (add-hook 'eshell-post-command-hook 'helm-system-packages-refresh nil t)
      (goto-char (point-max))
      (insert (mapconcat 'identity arg-list " "))
      (eshell-send-input))))

(defun helm-system-packages-browse-url (urls)
  "Browse homepage URLs of `helm-marked-candidates'.

With prefix argument, insert the output at point."
  (cond
   ((not urls) (message "No result"))
   (helm-current-prefix-arg (insert urls))
   (t (mapc 'browse-url (helm-comp-read "URL: " urls :must-match t :exec-when-only-one t :marked-candidates t)))))

;; TODO: Find name that makes more sense interactively.
(defun helm-system-packages-init ()
  "Cache package lists and create Helm buffer."
  (interactive)
  (when (or (not helm-system-packages--all) (called-interactively-p 'interactive))
    (setq helm-system-packages--all nil)
    (helm-system-packages-refresh))
  ;; TODO: We should only create the buffer if it does not already exist.
  ;; On the other hand, we need to be able to override the package list.
  ;; (unless (helm-candidate-buffer) ...
  (helm-init-candidates-in-buffer
      'global
    helm-system-packages--all))

;;;###autoload
(defun helm-system-packages ()
  "Helm user interface for system packages."
  (interactive)
  (let ((managers '("emerge" "dpkg" "pacman")))
    (while (and managers (not (executable-find (car managers))))
      (setq managers (cdr managers)))
    (if (not managers)
        (message "No supported package manager was found")
      (let ((manager (car managers)))
        (require (intern (concat "helm-system-packages-" manager)))
        (fset 'helm-system-packages-refresh (intern (concat "helm-system-packages-" manager "-refresh")))
        (funcall (intern (concat "helm-system-packages-" manager)))))))

(provide 'helm-system-packages)

;;; helm-system-packages.el ends here
