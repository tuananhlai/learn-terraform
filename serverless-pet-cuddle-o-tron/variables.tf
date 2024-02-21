variable "sender_email_identity" {
  type = string
  description = "The SES email identity of the sender. It must already be VERIFIED."
}

variable "receiver_email_identity" {
  type = string
  description = "The SES email identity of the receiver. It must already be VERIFIED."
}