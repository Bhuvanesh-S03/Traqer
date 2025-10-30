// firebase-config.js  — no Storage (works on Spark plan)
import { initializeApp } from "https://www.gstatic.com/firebasejs/11.6.1/firebase-app.js";
import { getFirestore } from "https://www.gstatic.com/firebasejs/11.6.1/firebase-firestore.js";
import { getAuth } from "https://www.gstatic.com/firebasejs/11.6.1/firebase-auth.js";
import {
  getDatabase,
  ref as rtdbRef,
  set as rtdbSet,
  onValue as rtdbOnValue,
  get as rtdbGet
} from "https://www.gstatic.com/firebasejs/11.6.1/firebase-database.js";

// ---------- put your firebase config here ----------
const firebaseConfig = {
  apiKey: "AIzaSyDSfIHFrTrVpvq2gVlidOGVAxBo7LYpdoc",
  authDomain: "traqer-76e85.firebaseapp.com",
  projectId: "traqer-76e85",
  databaseURL: "https://traqer-76e85-default-rtdb.asia-southeast1.firebasedatabase.app",
  storageBucket: "traqer-76e85.appspot.com",
  messagingSenderId: "166593920809",
  appId: "1:166593920809:web:855e84c4e57dcbcba78138",
  measurementId: "G-314D54428Y"
};
// ----------------------------------------------------

const app = initializeApp(firebaseConfig);
const db = getFirestore(app);
const auth = getAuth(app);
const rtdb = getDatabase(app);

// Export everything app.js will need
export { app, db, auth, rtdb, rtdbRef, rtdbSet, rtdbOnValue, rtdbGet };
