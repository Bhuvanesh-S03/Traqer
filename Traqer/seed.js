// seed.js
import admin from "firebase-admin";
import serviceAccount from "./serviceAccountKey.json" assert { type: "json" };

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();
const auth = admin.auth();

async function createUserWithRole(email, password, role, displayName) {
  try {
    // 1️⃣ Create user in Firebase Auth
    const userRecord = await auth.createUser({
      email,
      password,
      displayName,
    });

    // 2️⃣ Assign custom claim (role)
    await auth.setCustomUserClaims(userRecord.uid, { role });

    // 3️⃣ Store user info in Firestore
    await db.collection("users").doc(userRecord.uid).set({
      email,
      displayName,
      role,
      createdAt: new Date(),
    });

    console.log(`✅ Created ${role} user: ${displayName}`);
  } catch (error) {
    console.error(`❌ Error creating ${role}:`, error);
  }
}

async function seedUsers() {
  await createUserWithRole("admin@school.com", "Admin@123", "admin", "Admin User");
  await createUserWithRole("driver1@school.com", "Driver@123", "driver", "Driver 1");
  await createUserWithRole("parent1@school.com", "Parent@123", "parent", "Parent 1");
  console.log("🎉 All users created successfully!");
}

seedUsers();
