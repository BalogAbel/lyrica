enum InvitationError {
  notFound,
  expired,
  alreadyRedeemed,
  alreadyMember,
  emailMismatch,
  rateLimited,
  network,
  unknown,
}

/// Maps the `status` field of the `redeem_invitation` RPC response.
///
/// The backend reports business outcomes as returned statuses rather than
/// raised errors so that each attempt can be audited; see ADR-025.
InvitationError invitationErrorFromStatus(String? status) {
  switch (status) {
    case 'not_found':
      return InvitationError.notFound;
    case 'expired':
      return InvitationError.expired;
    case 'already_redeemed':
      return InvitationError.alreadyRedeemed;
    case 'already_member':
      return InvitationError.alreadyMember;
    case 'email_mismatch':
      return InvitationError.emailMismatch;
    case 'rate_limited':
      return InvitationError.rateLimited;
    default:
      return InvitationError.unknown;
  }
}
