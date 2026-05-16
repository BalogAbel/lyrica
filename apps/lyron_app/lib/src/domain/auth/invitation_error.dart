enum InvitationError {
  notFound,
  expired,
  alreadyRedeemed,
  alreadyMember,
  network,
  unknown,
}

InvitationError invitationErrorFromMessage(String? message) {
  switch (message) {
    case 'invitation_not_found':
      return InvitationError.notFound;
    case 'invitation_expired':
      return InvitationError.expired;
    case 'invitation_already_redeemed':
      return InvitationError.alreadyRedeemed;
    case 'already_member':
      return InvitationError.alreadyMember;
    default:
      return InvitationError.unknown;
  }
}
