;;; -*- lexical-binding: t -*-
;;; gntp.el --- Growl Notification Protocol for Emacs

;; Author: Engelke Eschner <tekai@gmx.li>
;; Version: 0.001
;; Created: 2013-03-21

;; LICENSE
;; Copyright (c) 2013 Engelke Eschner
;; All rights reserved.

;; Redistribution and use in source and binary forms, with or without
;; modification, are permitted provided that the following conditions
;; are met:
;;     * Redistributions of source code must retain the above copyright
;;       notice, this list of conditions and the following disclaimer.
;;     * Redistributions in binary form must reproduce the above
;;       copyright notice, this list of conditions and the following
;;       disclaimer in the documentation and/or other materials provided
;;       with the distribution.
;;     * Neither the name of the gntp.el nor the names of its
;;       contributors may be used to endorse or promote products derived
;;       from this software without specific prior written permission.

;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
;; "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
;; LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
;; A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT
;; HOLDER> BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
;; EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
;; PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
;; PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
;; OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
;; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
;; OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


;; DESCRIPTION
;; This package implements the Growl Notification Protocol GNTP
;; described at http://www.growlforwindows.com/gfw/help/gntp.aspx

;; It is incomplete as it only lets you send but not receive
;; notifications.

(defgroup gntp nil
  "GNTP, send/register growl notifications via GNTP from within
emacs."
  :group 'external)

(defcustom gntp-application-name "Emacs/gntp.el"
  "Name of the application gntp registers itself"
  :type '(string))

(defcustom gntp-application-icon nil
  "Icon to display as the application icon. Either a URL or a
path to a file."
  :type '(string))

(defun gntp-register (notifications server &optional port)
  "Register NOTIFICATIONS at SERVER"
  (let ((message (gntp-build-message-register notifications)))
    (gntp-send message server port)))

(defun gntp-send (message server &optional port)
  (let* ((port (if port port 23053))
         (proc (open-network-stream
                "gntp"
                "*gntp*"
                server
                port
                :type 'plain
                ))
         (buf (process-buffer proc)))

    (process-send-string proc (concat message "\r\n\r\n\r\n"))

    ;; Watch us spin and stop Emacs from doing anything else!
    (while (equal (process-status proc) 'open)
      (when (not (accept-process-output proc 180))
        (delete-process proc)
        (error "Network timeout!")))
    (delete-process proc)
    (gntp-handle-reply buf))

(defun gntp-handle-reply (buffer)
  (with-current-buffer
      (goto-char (point-min))
    (if (looking-at "^GNTP/1.0 -ERROR")
        (error "Something went wrong take a look at buffer %s"
               (buffer-name buffer)))))

(defun gntp-build-message-register (notifications)
  "Build the message to register a notification types"
  (let ((lines (list "GNTP/1.0 REGISTER NONE"
                     (format "Application-Name: %s"
                             gntp-application-name)
                     (format "Notifications-Count: %d"
                             (length notifications))))
        (icon-uri (gntp-app-icon-uri))
        (icon-data (gntp-app-icon-data))
        (icons (list)))

    ;; append icon uri
    (when icon-uri
      (nconc lines (list (format "Application-Icon: %s" icon-uri)))
      ;; and data when it exists
      (when icon-data
        (setq icons (cons icon-data icons))))

    (dolist (notice notifications)
      ;; "For each notification being registered:
      ;; Each notification being registered should be seperated by a
      ;; blank line, including the first notification
      (nconc lines (cons "" (gntp-notification-lines notice)))
      ;; c
      (let ((icon (gntp-notice-icon-data notice)))
        (when icon
          (nconc icons (list "" icon)))))

    ;; icon data must come last
    (when icons
      (nconc lines (cons "" icons)))

    (mapconcat 'identity (remove nil lines) "\r\n")))

(defun gntp-notification-lines (notice)
  "Transform NOTICE into a list of strings"
  (let ((display-name (gntp-notice-get notice :display))
        (enabled (gntp-notice-get notice :enabled))
        (icon-uri (gntp-notice-icon-uri notice)))
  (list
   ;; Required - The name (type) of the notification being registered
   (concat "Notification-Name: " (gntp-notice-name notice))
   ;; Optional - The name of the notification that is displayed to
   ;; the user (defaults to the same value as Notification-Name)
   (when display-name
     (concat "Notification-Display-Name: " display-name))
   ;; Optional - Indicates if the notification should be enabled by
   ;; default (defaults to False)
   (when enabled
     "Notification-Enabled: True")
   ;; Optional - The default icon to use for notifications of this type
   (when icon-uri
     (concat "Notification-Icon: " icon-uri)))))

;; notice
;;(list name ; everthing else is optional
;;      :display "name to display"
;;      :enabled nil
;;      :icon "url or file")

(defun gntp-notify (name title text)
  "Send a previously registered notification"

  (format "GNTP/1.0 NOTIFY NONE\r\n\
Application-Name: %s\r\n\
Notification-Name: %s\r\n\
Notification-Title: %s\r\n\
Notification-Text: %s\r\n\
\r\n"
          gntp-application-name name title
          ;; no CRLF in the text to avoid accidentel msg end
          (replace-regexp-in-string "\r\n" "\n" text))))

(defun gntp-notice-icon-uri (notice)
  (gntp-icon-uri (gntp-notice-get notice :icon)))

(defun gntp-notice-icon-data (notice)
  (gntp-icon-data (gntp-notice-get notice :icon)))

(defun gntp-app-icon-uri ()
  "Return the value to be used in the Application-Icon header"
  (gntp-icon-uri gntp-application-icon))

(defun gntp-app-icon-data ()
  "Return the value to be used in the Application-Icon header"
  (gntp-icon-data gntp-application-icon))

(defun gntp-icon-uri (icon)
  "Get the URI of ICON."
  (when icon
    (cond ((string-equal (substring icon 0 7) "http://") icon)
          ((and (file-exists-p icon) (file-readable-p icon))
           (concat "x-growl-resource://" (md5 icon))))))

(defun gntp-icon-data (icon)
  "Get the URI of ICON."
  (when (and icon (not (string-equal (substring icon 0 7) "http://"))
             (file-exists-p icon) (file-readable-p icon))
    (let ((id (md5 icon))
          (data (gntp-file-string icon)))
      (format "Identifier: %s\r\nLength: %d\r\n\r\n%s"
              id (length data) data))))

(defun gntp-notice-name (notice)
  "Get the name of NOTICE. The name must be either a symbol or
string"
  (let ((name (car notice)))
    (if (symbolp name)
        (symbol-name name)
      name)))

(defun gntp-notice-get (notice property)
  (plist-get (cdr notice) property))

(defun gntp-file-string (file)
  "Read the contents of a file and return as a string."
  (with-temp-buffer
    (insert-file-contents-literally file)
    (buffer-string)))

(provide 'gntp)
