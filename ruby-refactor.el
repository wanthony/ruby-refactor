;;; ruby-refactor.el --- A minor mode for Emacs that presents various Ruby refactoring helpers.

;; Copyright (C) 2013 Andrew J Vargo

;; Author: Andrew J Vargo <ajvargo@gmail.com>
;; Keywords: refactor ruby

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Ruby refactor is inspired by the Vim plugin vim-refactoring-ruby,
;; currently found at https://github.com/ecomba/vim-ruby-refactoring.

;; I've implemented 3 refactorings
;;  - Extract to Method
;;  - Add Parameter
;;  - Extract to Let

; ## Install
;; Add this file to your load path.
;; (require 'ruby-refactor)


;; ## Extract to Method:
;; Select a region of text and invoke 'ruby-refactor-extract-to-method'.
;; You'll be prompted for a method name. The method will be created
;; above the method you are in with the method contents being the
;; selected region. The region will be replaced w/ a call to method.


;; ## Add Parameter:
;; 'ruby-refactor-add-parameter'
;; This simply prompts you for a parameter to add to the current
;; method definition. If you are on a text, you can just hit enter
;; as it will use it by default. There is a custom variable to set
;; if you like parens on your params list.  Default values and the
;; like shouldn't confuse it.

;; ## Extract to Let:
;; This is really for use with RSpec

;; 'ruby-refactor-extract-to-let'
;; There is a variable for where the 'let' gets placed. It can be
;; "top" which is top-most in the file, or "closest" which just
;; walks up to the first describe/context it finds.
;; You can also specify a different regex, so that you can just
;; use "describe" if you want.
;; If you are on a line:
;;   a = Something.else.doing
;;     becomes
;;   let(:a){ Something.else.doing }

;; If you are selecting a region:
;;   a = Something.else
;;   a.stub(:blah)
;;     becomes
;;   let :a do
;;     _a = Something.else
;;     _a.stub(:blah)
;;     _a
;;   end

;; In both cases, you need the line, first line to have an ' = ' in it,
;; as that drives conversion.

;; There is also the bonus that the let will be placed *after* any other
;; let statements. It appends it to bottom of the list.

;; Oh, if you invoke with a prefix arg (C-u, etc.), it'll swap the placement
;; of the let.  If you have location as top, a prefix argument will place
;; it closest.  I kinda got nutty with this one.


;; ## TODO
;; From the vim plugin, these remain to be done (I don't plan to do them all.)
;;  - extract local variable
;;  - remove inline temp (sexy!)
;;  - convert post conditional


(defvar ruby-refactor-mode-map (make-sparse-keymap)
  "Keymap to use in ruby refactor minor mode.")

;;; Customizations
(defgroup ruby-refactor nil
  "Refactoring helpers for Ruby."
  :version "0.1"
  :group 'files)


(defcustom ruby-refactor-add-parens nil
  "Add parens when adding a parameters to a function. Will be converted if params already exist"
  :group 'ruby-refactor
  :type 'boolean
  )

(defcustom ruby-refactor-trim-regexp "[ \t\n\(\)]*"
  "Regex to use for trim functions. Will be applied to both front and back of string"
  :group 'ruby-refactor
  :type 'string
)

(defcustom ruby-refactor-let-placement-regexp "^[ \t]*\\(describe\\|context\\)"
  "Regex searched for to determine where to put let statemement.
See `ruby-refactor-let-position' to specify proximity to assignment
being altered."
  :group 'ruby-refactor
  :type 'string
)

(defcustom ruby-refactor-let-position 'top
  "Where to place 'let' statement. 'closest places it after the
most recent context or describe.  'top (default) places it after
 opening describe "
  :type '(choice (const :tag "place top-most" top)
                 (const :tag "place closest" closest)))

;;; Helper functions
(defun ruby-refactor-trim-string (string)
  "Trims text from both front and back of a string"
   (replace-regexp-in-string (concat ruby-refactor-trim-regexp "$") ""
                             (replace-regexp-in-string (concat "^" ruby-refactor-trim-regexp) "" string)))

(defun ruby-refactor-trim-list (list)
  "Applies `ruby-refactor-trim-string' to each item in list, and returns newly trimmed list"
  (mapcar #'ruby-refactor-trim-string list))

(defun ruby-refactor-goto-def-start ()
  "Moves point to start of first def to appear previously "
  (search-backward-regexp "^\\s *def"))

(defun ruby-refactor-get-input-with-default (prompt default-value)
  "Gets user input with a default value"
  (list (read-string (format "%s (%s): " prompt default-value) nil nil default-value)))

(defun ruby-refactor-new-params (existing-params new-variable)
  "Appends or creates parameter list, doing the right thing for parens"
  (let ((param-list (mapconcat 'identity
                      (ruby-refactor-trim-list (remove "" (append (split-string existing-params ",") (list new-variable))))
                      ", " )))
    (if ruby-refactor-add-parens
        (format "(%s)" param-list)
      (format " %s" param-list))))

(defun ruby-refactor-goto-first-non-let-line ()
  "Place point at beginning of first non let( containing line"
  (while (ruby-refactor-line-has-let-p)
    (forward-line 1)))

(defun ruby-refactor-line-has-let-p ()
  (string-match "let(" (thing-at-point 'line)))

;;; API
(defun ruby-refactor-extract-to-method (region-start region-end)
  "Extracts region to method"
  (interactive "r")
  (save-restriction
    (save-match-data
      (widen)
      (let ((function-guts (buffer-substring-no-properties region-start region-end))
            (function-name (read-from-minibuffer "Method name? ")))
        (delete-region region-start region-end)
        (ruby-indent-line)
        (insert function-name)
        (ruby-refactor-goto-def-start)
        (insert "\tdef " function-name "\n" function-guts "\nend\n\n")
        (ruby-refactor-goto-def-start)
        (ruby-indent-exp)
        (ruby-forward-sexp)
        (search-forward function-name)
        ))))

(defun ruby-refactor-add-parameter (variable-name)
  "Add a parameter to the method point is in"
  (interactive (ruby-refactor-get-input-with-default "Variable name" (thing-at-point 'symbol)))
  (save-excursion
    (save-restriction
      (save-match-data
        (widen)
        (ruby-refactor-goto-def-start)
        (search-forward "def")
        (let* ((params-start-point (search-forward-regexp (concat ruby-symbol-re "+")))
              (params-end-point (line-end-position))
              (params-string (buffer-substring-no-properties params-start-point params-end-point)))
          (delete-region params-start-point params-end-point)
          (goto-char params-start-point)
          (insert (ruby-refactor-new-params params-string variable-name))
          )))))

(defun ruby-refactor-extract-to-let(&optional flip-location)
  "Converts initialization on current line to 'let', ala RSpec
When called with a prefix argument, flips the default location
for placement.
If a region is selected, the first line needs to have an assigment.
The let style is then a do block containing the region.
If a region is not selected, the transformation uses the current line."
  (interactive "P")
  (save-excursion
    (save-restriction
      (save-match-data
        (widen)
        (let (text-begin text-end text)
          (if (region-active-p)
              (setq text-begin (region-beginning) text-end (region-end))
            (setq text-begin (car (bounds-of-thing-at-point 'line)) text-end (cdr (bounds-of-thing-at-point 'line))))
          (setq text (buffer-substring-no-properties text-begin text-end))

          (delete-region text-begin text-end)
          (let ((position-test (if (null flip-location)
                                   #'(lambda(left right)(eq left right))
                                 #'(lambda(left right)(not (eq left right))))))
            (cond ((funcall position-test 'top ruby-refactor-let-position)
                   (goto-char 0)
                   (search-forward-regexp ruby-refactor-let-placement-regexp))
                  ((funcall position-test 'closest ruby-refactor-let-position)
                   (search-backward-regexp ruby-refactor-let-placement-regexp))))
          (forward-line 1)
          (ruby-refactor-goto-first-non-let-line)
          (ruby-indent-line)
          (if (region-active-p)
              (progn
                (let* ((text-lines (ruby-refactor-trim-list (split-string text "\n")))
                       (variable-name (car (ruby-refactor-trim-list (split-string (car text-lines) " = "))))
                       (faux-variable-name (concat "_" variable-name)))
                  (insert (format "let :%s do" variable-name))
                  (mapc #'(lambda(line) (newline)
                            (insert (replace-regexp-in-string variable-name faux-variable-name line)))
                        text-lines)
                  (insert "\n" faux-variable-name "\n" "end")
                  (newline-and-indent)
                  (search-backward "let")
                  (ruby-indent-exp)
                  (search-forward "end")))
            (progn
              (let ((line-components (ruby-refactor-trim-list (split-string text " = "))))
                (insert (format "let(:%s){ %s }" (car line-components) (cadr line-components))))))
          (newline-and-indent)
          (beginning-of-line)
          (unless (looking-at "^[ \t]*$") (newline-and-indent))))))
  (delete-blank-lines)
  )

(defun ruby-refactor-extract-local-variable()
  "Extracts selected text to local variable"
  (interactive)
  (message "Not Yet Implmented"))

(defun ruby-refactor-remove-inline-temp()
  "Replaces temporary variable with direct call to method"
  (interactive)
  (message "Not Yet Implmented"))

(defun ruby-refactor-convert-post-conditional()
  "Convert post conditional expression to conditional expression"
  (interactive)
  (message "Not Yet Implmented"))

;;; Official setup and the like
(defun ruby-refactor-start ()
  (use-local-map ruby-refactor-mode-map)
  (message "Ruby-Refactor mode enabled"))

(defun ruby-refactor-stop ()
  (message "Ruby-Refactor mode disabled"))

(if ruby-refactor-mode-map
    nil
  (setq ruby-refactor-mode-map (make-sparse-keymap))
  (define-key ruby-refactor-mode-map "\C-c\C-re" 'ruby-refactor-extract-to-method)
  (define-key ruby-refactor-mode-map "\C-c\C-rp" 'ruby-refactor-add-parameter)
  (define-key ruby-refactor-mode-map "\C-c\C-rl" 'ruby-refactor-extract-to-let))

(define-minor-mode ruby-refactor-mode
  "Ruby Refactor minor mode"
  :global nil
  :group 'ruby-refactor
  :keymap ruby-refactor-mode-map
  :lighter " RubyRef"
  (if ruby-refactor-mode
      (ruby-refactor-start)
    (ruby-refactor-stop)))

(provide 'ruby-refactor)
