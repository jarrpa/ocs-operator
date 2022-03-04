1. Create keys 
  `bash generate_keys.sh`
2. Generate onboarding ticket:
  `bash ./ticketgen.sh key.pem > onboarding_ticket.txt`

key.pem               --> Stays with the user.
pubkey.pem            --> Goes to the provider.
onboarding_ticket.txt --> Goes to the consumer.
