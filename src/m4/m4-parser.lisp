;;;; evol - m4-parser.lisp
;;;; Copyright (C) 2010  Alexander Kahl <e-user@fsfe.org>
;;;; This file is part of evol.
;;;; evol is free software; you can redistribute it and/or modify
;;;; it under the terms of the GNU General Public License as published by
;;;; the Free Software Foundation; either version 3 of the License, or
;;;; (at your option) any later version.
;;;;
;;;; evol is distributed in the hope that it will be useful,
;;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;;; GNU General Public License for more details.
;;;;
;;;; You should have received a copy of the GNU General Public License
;;;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

(in-package :evol)

(defmacro with-tokens-active ((&rest tokens) &body body)
  `(let ,(mapcar #'(lambda (token)
                     (list token ""))
                 (set-difference '(*m4-quote-start* *m4-quote-end* *m4-comment-start* *m4-comment-end* *m4-macro-name*)
                                 tokens))
     ,@body))

(define-condition m4-parse-error (error)
  ((message :initarg :message
            :reader m4-parse-error-message)
   (row   :initarg :row
          :reader m4-parse-error-row)
   (column :initarg :column
           :reader m4-parse-error-column)))

(defun split-merge (string-list split-token)
  (labels ((acc (rec string rest)
             (let ((token (car rest)))
               (cond ((null token) (nreverse (cons string rec)))
                     ((equal split-token token)
                      (acc (cons string rec) "" (cdr rest)))
                     ((not (stringp token)) ; macro-token; a separator MUST follow
                      (acc rec token (cdr rest)))
                     (t (acc rec (concatenate 'string string token) (cdr rest)))))))
          (acc (list) "" string-list)))

(defun call-m4-macro (macro args lexer)
  (let ((*m4-parse-row* (lexer-row lexer))
        (*m4-parse-column* (lexer-column lexer)))
    (if (not args)
        (funcall macro nil)
      (apply macro nil (mapcar #'(lambda (string)
                                   (if (stringp string)
                                       (string-left-trim '(#\Newline #\Space) string)
                                     string)) ; macro-token
                               (split-merge args :separator))))))

(defun m4-out (word)
  (with-m4-diversion-stream (out)
    (write-string word out)))


(defun parse-m4-comment (lexer image)
  (let ((row (lexer-row lexer))
        (column (lexer-column lexer)))
    (labels ((m4-comment (rec)
               (multiple-value-bind (class image)
                   (with-tokens-active (*m4-comment-end*)
                     (stream-read-token lexer))
                 (cond ((null class)
                        (error 'm4-parse-error :message "end of file in comment" :row row :column column))
                       ((equal :comment-end class)
                        (apply #'concatenate 'string
                               (nreverse (cons image rec))))
                   (t (m4-comment (cons image rec)))))))
      (m4-comment (list image)))))

(defun parse-m4-quote (lexer)
  (let ((row (lexer-row lexer))
        (column (lexer-column lexer)))
    (labels ((m4-quote (rec quoting-level)
               (multiple-value-bind (class image)
                   (if (= 0 (or (search *m4-quote-end* *m4-quote-start*)
                                -1)) ; "If end is a prefix of start, the
                                     ;  end-quote will be recognized in preference to a
                                     ;  nested begin-quote"
                       (with-tokens-active (*m4-quote-end*)
                         (stream-read-token lexer))
                   (with-tokens-active (*m4-quote-start* *m4-quote-end*)
                     (stream-read-token lexer)))
                 (cond ((null class)
                        (error 'm4-parse-error :message "end of file in string" :row row :column column))
                        ((equal :quote-end class)
                         (if (= 1 quoting-level)
                             (apply #'concatenate 'string (nreverse rec))
                           (m4-quote (cons image rec) (1- quoting-level))))
                        ((equal :quote-start class)
                         (m4-quote (cons image rec) (1+ quoting-level)))
                        (t (m4-quote (cons image rec) quoting-level))))))
      (m4-quote (list) 1))))

(defun parse-m4-macro-arguments (lexer)
  (let ((row (lexer-row lexer))
        (column (lexer-column lexer)))
    (labels ((m4-group-merge (string rec paren-level)
               (if (> paren-level 1)
                   (cons (concatenate 'string (car rec) string)
                         (cdr rec))
                 (cons string rec)))
             (m4-macro-arguments (rec paren-level)
               (multiple-value-bind (class image)
                   (with-tokens-active (*m4-quote-start* *m4-macro-name* *m4-comment-start*)
                     (stream-read-token lexer))
                 (cond ((null class)
                        (error 'm4-parse-error :message "EOF with unfinished argument list" :row row :column column))
                       ((equal :close-paren class)
                        (if (= 1 paren-level)
                            (nreverse rec)
                          (m4-macro-arguments (m4-group-merge image rec paren-level) (1- paren-level))))
                       ((equal :open-paren class)
                        (m4-macro-arguments (m4-group-merge image rec paren-level) (1+ paren-level)))
                       ((equal :quote-start class)
                        (m4-macro-arguments (m4-group-merge (parse-m4-quote lexer) rec paren-level) paren-level))
                       ((equal :comment-start class)
                        (m4-macro-arguments (m4-group-merge (parse-m4-comment lexer image) rec paren-level) paren-level))
                       ((equal :macro-name class)
                        (m4-macro-arguments (m4-group-merge (parse-m4-macro lexer image) rec paren-level) paren-level))
                       ((and (= 1 paren-level)
                             (equal :comma class))
                        (m4-macro-arguments (cons :separator rec) paren-level))
                       (t (m4-macro-arguments (m4-group-merge image rec paren-level) paren-level))))))
      (m4-macro-arguments (list "") 1))))

(defun parse-m4-dnl (lexer)
  (with-tokens-active ()
    (do ((class (stream-read-token lexer) (stream-read-token lexer)))
        ((or (equal :newline class)
             (null class)) ""))))

(defun parse-m4-macro (lexer macro-name)
  (let ((macro (m4-macro macro-name)))
    (if (not macro)
        macro-name
      (handler-case
       (multiple-value-bind (class image)
           (stream-read-token lexer t)
         (declare (ignore image))
         (if (equal :open-paren class)
             (progn
               (stream-read-token lexer) ; consume token
               (call-m4-macro macro (parse-m4-macro-arguments lexer) lexer))
           (call-m4-macro macro nil lexer)))
       (macro-dnl-invocation-condition ()
         (parse-m4-dnl lexer))
       (macro-defn-invocation-condition (condition)
         (m4-push-macro lexer (macro-defn-invocation-result condition))
         "")
       (macro-invocation-condition (condition)
         (lexer-unread-sequence lexer (macro-invocation-result condition))
         "")))))

(defun parse-m4 (lexer)
  (do* ((token (multiple-value-list (stream-read-token lexer))
               (multiple-value-list (stream-read-token lexer)))
        (class (car token) (car token))
        (image (cadr token) (cadr token)))
      ((null class)
       (when *m4-wrap-stack*
         (lexer-unread-sequence lexer (apply #'concatenate 'string *m4-wrap-stack*))
         (let ((*m4-wrap-stack* (list)))
           (parse-m4 lexer)))
       (let ((*m4-diversion* 0))
         (mapcar #'m4-out (flush-m4-diversions))))
    (m4-out
     (cond ((equal :quote-start class)
            (parse-m4-quote lexer))
           ((equal :comment-start class)
            (parse-m4-comment lexer image))
           ((equal :macro-name class)
            (parse-m4-macro lexer image))
           ((equal :macro-token class)
            (if (macro-token-p image)
                (string (macro-token-name image))
              ""))
           (t image)))))

(defun process-m4 (input-stream output-stream &key (include-path (list)) (prepend-include-path (list)))
  (let* ((*m4-quote-start* "`")
         (*m4-quote-end* "'")
         (*m4-comment-start* "#")
         (*m4-comment-end* "\\n")
         (*m4-macro-name* "[_a-zA-Z]\\w*")
         (*m4-wrap-stack* (list))
         (*m4-include-path* (append (reverse prepend-include-path) (list ".") include-path))
         (*m4-diversion* 0)
         (*m4-diversion-table* (make-m4-diversion-table output-stream))
         (lexer (make-instance 'm4-input-stream
                               :stream input-stream
                               :rules '((*m4-comment-start* . :comment-start)
                                        (*m4-comment-end* . :comment-end)
                                        (*m4-macro-name* . :macro-name)
                                        (*m4-quote-start* . :quote-start)
                                        (*m4-quote-end* . :quote-end)
                                        ("," . :comma)
                                        ("\\n" . :newline)
                                        ("\\(" . :open-paren)
                                        ("\\)" . :close-paren)
                                        ("." . :token)))))
    (with-m4-lib (parse-m4 lexer))))
