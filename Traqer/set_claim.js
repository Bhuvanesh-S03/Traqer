// set_claims.js
import admin from "firebase-admin";
import serviceAccount from "./serviceAccountKey.json" with { type: "json" };

// Replace this with the UID you copied from the Firebase Console
const ADMIN_UID = "GJhnC0dIkwR7fe9WM8flZRP8ENN2"; 

// Initialize Firebase Admin SDK
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});
const auth = admin.auth();

async function setAdminClaim() {
  try {
    // 1. Set the custom claim { role: 'admin' }
    await auth.setCustomUserClaims(ADMIN_UID, { role: 'admin' });

    // 2. Verify the claim was set (Optional, but helpful for debugging)
    const user = await auth.getUser(ADMIN_UID);
    console.log(`✅ Successfully set role: 'admin' for user: ${user.email}`);
    console.log("Current Claims:", user.customClaims);
    
    // 3. IMPORTANT: Tell the user to log out and back in
    console.log("-----------------------------------------");
    console.log("ACTION REQUIRED: Log out of your Admin Dashboard and log back in.");
    console.log("This forces the browser to refresh the security token with the new claim.");

  } catch (error) {
    console.error("❌ Error setting custom claim:", error);
  }
}

setAdminClaim();