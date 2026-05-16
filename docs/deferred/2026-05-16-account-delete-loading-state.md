# Account Delete: Missing Loading State

**Slice:** auth-invite-sso (PR #42)  
**File:** `apps/lyron_app/lib/src/presentation/account/account_screen.dart`

## Problem

The "Delete account" button triggers `appAuthController.deleteAccount()` but has no in-flight guard. The button remains tappable while the async delete is in progress, allowing the user to submit a second delete call before the first completes.

`deleteAccount()` calls `supabase.auth.admin.deleteUser()` which is not idempotent on a live session — a second call on the same session may return a 404 or trigger an unexpected error path. Even if Supabase handles duplicates gracefully, the UI gives no feedback that work is happening.

## Deferred Because

Adding a `_deleting` state flag requires threading it through `_AccountScreenState`, converting the button to a disabled/loading variant, and deciding on a timeout policy. This is self-contained but it was out of scope for the invite-auth slice, which focused on the happy path.

## Expected Behavior When Fixed

1. After the user confirms the alert dialog, the Delete button is replaced by a `CircularProgressIndicator` (or becomes disabled with `onPressed: null`).
2. A second tap is a no-op while the delete is in-flight.
3. On error, the loading state clears and a SnackBar is shown.

## Trigger Condition

Address this before shipping the account-management slice. Any PR that touches `account_screen.dart` or the `deleteAccount` application layer must close this gap.
