// ============================================
// JUGEND DATING APP - JAVASCRIPT
// ============================================

// ============================================
// 1. SUPABASE SETUP
// ============================================

// WICHTIG: Ersetze diese Werte mit deinen echten Supabase-Daten!
const SUPABASE_URL = 'https://uokrcpaiscuoslgmjscx.supabase.co'; // Hier deine URL eintragen!
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVva3JjcGFpc2N1b3NsZ21qc2N4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAxMjk3ODEsImV4cCI6MjA4NTcwNTc4MX0.MgQDX4ZY_YE0yfFi0ltKWVDjCjB5vpht0WGezhixSF8'; // Hier deinen anon Key eintragen!

const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ============================================
// 2. GLOBALE VARIABLEN
// ============================================

let currentUser = null;
let currentProfile = null;

// ============================================
// 3. APP INITIALISIERUNG
// ============================================

document.addEventListener('DOMContentLoaded', async () => {
    console.log('🚀 App wird initialisiert...');
    
    // Service Worker registrieren (PWA)
    if ('serviceWorker' in navigator) {
        try {
            await navigator.serviceWorker.register('/sw.js');
            console.log('✅ Service Worker registriert');
        } catch (error) {
            console.log('❌ Service Worker Fehler:', error);
        }
    }
    
    // Event Listeners setup
    setupEventListeners();
    
    // Geburtsdatum-Dropdowns füllen
    fillBirthdateDropdowns();
    
    // Session prüfen
    await checkSession();
});

// ============================================
// 4. EVENT LISTENERS
// ============================================

function setupEventListeners() {
    // Sicherheitshinweise
    const checkboxes = document.querySelectorAll('.safety-checkboxes input[type="checkbox"]');
    const safetyAcceptBtn = document.getElementById('safety-accept-btn');
    
    checkboxes.forEach(checkbox => {
        checkbox.addEventListener('change', () => {
            const allChecked = Array.from(checkboxes).every(cb => cb.checked);
            safetyAcceptBtn.disabled = !allChecked;
        });
    });
    
    safetyAcceptBtn.addEventListener('click', handleSafetyAccept);
    
    // Auth Forms
    document.getElementById('switch-to-register').addEventListener('click', (e) => {
        e.preventDefault();
        switchAuthForm('register');
    });
    
    document.getElementById('switch-to-login').addEventListener('click', (e) => {
        e.preventDefault();
        switchAuthForm('login');
    });
    
    document.getElementById('login-btn').addEventListener('click', handleLogin);
    document.getElementById('register-btn').addEventListener('click', handleRegister);
    document.getElementById('logout-btn').addEventListener('click', handleLogout);
    
    // Geburtsdatum Check für Eltern-Email
    document.getElementById('birth-day').addEventListener('change', checkAge);
    document.getElementById('birth-month').addEventListener('change', checkAge);
    document.getElementById('birth-year').addEventListener('change', checkAge);
    
    // Enter-Taste für Login
    document.getElementById('login-password').addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
            handleLogin();
        }
    });
}

// ============================================
// 5. GEBURTSDATUM DROPDOWNS FÜLLEN
// ============================================

function fillBirthdateDropdowns() {
    const daySelect = document.getElementById('birth-day');
    const yearSelect = document.getElementById('birth-year');
    
    // Tage 1-31
    for (let i = 1; i <= 31; i++) {
        const option = document.createElement('option');
        option.value = i;
        option.textContent = i;
        daySelect.appendChild(option);
    }
    
    // Jahre (aktuelles Jahr - 14 bis aktuelles Jahr - 100)
    const currentYear = new Date().getFullYear();
    const minYear = currentYear - 100;
    const maxYear = currentYear - 14; // Mindestens 14
    
    for (let i = maxYear; i >= minYear; i--) {
        const option = document.createElement('option');
        option.value = i;
        option.textContent = i;
        yearSelect.appendChild(option);
    }
}

// ============================================
// 6. ALTER PRÜFEN (für Eltern-Email)
// ============================================

function checkAge() {
    const day = document.getElementById('birth-day').value;
    const month = document.getElementById('birth-month').value;
    const year = document.getElementById('birth-year').value;
    
    if (!day || !month || !year) return;
    
    const birthDate = new Date(year, month - 1, day);
    const age = calculateAge(birthDate);
    
    const parentEmailGroup = document.getElementById('parent-email-group');
    const parentEmailInput = document.getElementById('parent-email');
    
    if (age < 16) {
        parentEmailGroup.style.display = 'block';
        parentEmailInput.required = true;
    } else {
        parentEmailGroup.style.display = 'none';
        parentEmailInput.required = false;
    }
}

function calculateAge(birthDate) {
    const today = new Date();
    let age = today.getFullYear() - birthDate.getFullYear();
    const monthDiff = today.getMonth() - birthDate.getMonth();
    
    if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
        age--;
    }
    
    return age;
}

// ============================================
// 7. SICHERHEITSHINWEISE
// ============================================

async function handleSafetyAccept() {
    try {
        showScreen('loading');
        
        // Sicherheitsbestätigung in DB speichern (falls eingeloggt)
        if (currentUser) {
            const { error } = await supabase
                .from('safety_confirmations')
                .upsert({
                    user_id: currentUser.id,
                    confirmed_at: new Date().toISOString(),
                    version: 1
                });
            
            if (error) throw error;
            
            // Zur App
            showScreen('app');
        } else {
            // Zum Login
            showScreen('auth');
        }
        
    } catch (error) {
        console.error('Fehler beim Speichern der Sicherheitsbestätigung:', error);
        showError('Ein Fehler ist aufgetreten. Bitte versuche es erneut.');
        showScreen('safety');
    }
}

// ============================================
// 8. SESSION PRÜFEN
// ============================================

async function checkSession() {
    try {
        const { data: { session } } = await supabase.auth.getSession();
        
        if (session) {
            currentUser = session.user;
            
            // Profil laden
            const { data: profile, error } = await supabase
                .from('profiles')
                .select('*')
                .eq('id', currentUser.id)
                .single();
            
            if (error) throw error;
            
            currentProfile = profile;
            
            // Prüfen ob Sicherheitshinweise akzeptiert
            const { data: confirmation } = await supabase
                .from('safety_confirmations')
                .select('*')
                .eq('user_id', currentUser.id)
                .single();
            
            if (!confirmation) {
                // Sicherheitshinweise zeigen
                showScreen('safety');
            } else {
                // Direkt zur App
                showScreen('app');
            }
        } else {
            // Nicht eingeloggt -> Sicherheitshinweise
            showScreen('safety');
        }
    } catch (error) {
        console.error('Session Check Fehler:', error);
        showScreen('safety');
    }
}

// ============================================
// 9. LOGIN
// ============================================

async function handleLogin() {
    const email = document.getElementById('login-email').value.trim();
    const password = document.getElementById('login-password').value;
    
    // Validierung
    if (!email || !password) {
        showError('Bitte fülle alle Felder aus!');
        return;
    }
    
    if (!isValidEmail(email)) {
        showError('Bitte gib eine gültige E-Mail-Adresse ein!');
        return;
    }
    
    try {
        showScreen('loading');
        
        const { data, error } = await supabase.auth.signInWithPassword({
            email: email,
            password: password
        });
        
        if (error) throw error;
        
        currentUser = data.user;
        
        // Profil laden
        const { data: profile, error: profileError } = await supabase
            .from('profiles')
            .select('*')
            .eq('id', currentUser.id)
            .single();
        
        if (profileError) throw profileError;
        
        currentProfile = profile;
        
        // Account-Status prüfen
        if (profile.account_status === 'banned') {
            await supabase.auth.signOut();
            showError(`Dein Account wurde gesperrt. Grund: ${profile.ban_reason || 'Regelverstoß'}`);
            showScreen('auth');
            return;
        }
        
        // Eltern-Verifizierung prüfen (unter 16)
        const age = calculateAge(new Date(profile.geburtsdatum));
        if (age < 16 && !profile.verified_parent) {
            showError('Deine Eltern müssen deine Nutzung noch bestätigen. Bitte prüfe deine E-Mails!');
            await supabase.auth.signOut();
            showScreen('auth');
            return;
        }
        
        // Online-Status setzen
        await supabase
            .from('profiles')
            .update({
                online_status: true,
                zuletzt_online: new Date().toISOString(),
                last_active_at: new Date().toISOString()
            })
            .eq('id', currentUser.id);
        
        // Sicherheitshinweise zeigen
        showScreen('safety');
        
    } catch (error) {
        console.error('Login Fehler:', error);
        
        if (error.message.includes('Invalid login credentials')) {
            showError('E-Mail oder Passwort falsch!');
        } else if (error.message.includes('Email not confirmed')) {
            showError('Bitte bestätige zuerst deine E-Mail-Adresse!');
        } else {
            showError('Login fehlgeschlagen: ' + error.message);
        }
        
        showScreen('auth');
    }
}

// ============================================
// 10. REGISTRIERUNG
// ============================================

async function handleRegister() {
    const username = document.getElementById('register-username').value.trim();
    const email = document.getElementById('register-email').value.trim();
    const password = document.getElementById('register-password').value;
    const day = document.getElementById('birth-day').value;
    const month = document.getElementById('birth-month').value;
    const year = document.getElementById('birth-year').value;
    const parentEmail = document.getElementById('parent-email').value.trim();
    
    // Validierung
    if (!username || !email || !password || !day || !month || !year) {
        showError('Bitte fülle alle Pflichtfelder aus!');
        return;
    }
    
    if (username.length < 3 || username.length > 20) {
        showError('Benutzername muss zwischen 3 und 20 Zeichen lang sein!');
        return;
    }
    
    if (!isValidEmail(email)) {
        showError('Bitte gib eine gültige E-Mail-Adresse ein!');
        return;
    }
    
    if (password.length < 8) {
        showError('Passwort muss mindestens 8 Zeichen lang sein!');
        return;
    }
    
    // Geburtsdatum validieren
    const birthDate = new Date(year, month - 1, day);
    const age = calculateAge(birthDate);
    
    if (age < 14) {
        showError('Du musst mindestens 14 Jahre alt sein!');
        return;
    }
    
    if (age > 100) {
        showError('Bitte gib ein gültiges Geburtsdatum ein!');
        return;
    }
    
    // Eltern-Email prüfen (unter 16)
    if (age < 16 && !parentEmail) {
        showError('Du bist unter 16! Bitte gib die E-Mail deiner Eltern an!');
        return;
    }
    
    if (age < 16 && !isValidEmail(parentEmail)) {
        showError('Bitte gib eine gültige E-Mail-Adresse deiner Eltern ein!');
        return;
    }
    
    try {
        showScreen('loading');
        
        // 1. Auth User erstellen
        const { data: authData, error: authError } = await supabase.auth.signUp({
            email: email,
            password: password,
            options: {
                data: {
                    username: username
                }
            }
        });
        
        if (authError) throw authError;
        
        if (!authData.user) {
            throw new Error('Registrierung fehlgeschlagen');
        }
        
        // 2. Profil erstellen
        const { error: profileError } = await supabase
            .from('profiles')
            .insert({
                id: authData.user.id,
                username: username,
                geburtsdatum: `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`,
                eltern_email: age < 16 ? parentEmail : null,
                verified_parent: age >= 16 ? true : false, // Über 16 brauchen keine Eltern-Verifizierung
                role: email === 'pajaziti.leon97080@gmail.com' ? 'owner' : 'user'
            });
        
        if (profileError) throw profileError;
        
        // 3. Eltern-Verifizierungs-Email senden (unter 16)
        if (age < 16 && parentEmail) {
            // TODO: Hier würde normalerweise eine Email an die Eltern gehen
            // Das machen wir in Phase 2 mit Vercel Functions
            console.log('Eltern-Email würde gesendet an:', parentEmail);
        }
        
        // Erfolg!
        showSuccess(
            age < 16 
                ? 'Account erstellt! Bitte prüfe deine E-Mails und bitte deine Eltern, ihre E-Mail zu bestätigen!' 
                : 'Account erstellt! Bitte bestätige deine E-Mail-Adresse!'
        );
        
        // Zurück zum Login
        setTimeout(() => {
            switchAuthForm('login');
            showScreen('auth');
        }, 3000);
        
    } catch (error) {
        console.error('Registrierungs-Fehler:', error);
        
        if (error.message.includes('duplicate key')) {
            if (error.message.includes('username')) {
                showError('Dieser Benutzername ist bereits vergeben!');
            } else if (error.message.includes('email')) {
                showError('Diese E-Mail-Adresse ist bereits registriert!');
            } else {
                showError('Dieser Benutzername oder E-Mail ist bereits vergeben!');
            }
        } else if (error.message.includes('User already registered')) {
            showError('Diese E-Mail-Adresse ist bereits registriert!');
        } else {
            showError('Registrierung fehlgeschlagen: ' + error.message);
        }
        
        showScreen('auth');
    }
}

// ============================================
// 11. LOGOUT
// ============================================

async function handleLogout() {
    try {
        // Online-Status auf false setzen
        if (currentUser) {
            await supabase
                .from('profiles')
                .update({
                    online_status: false,
                    zuletzt_online: new Date().toISOString()
                })
                .eq('id', currentUser.id);
        }
        
        await supabase.auth.signOut();
        
        currentUser = null;
        currentProfile = null;
        
        // Zurück zu Sicherheitshinweisen
        showScreen('safety');
        
        // Checkboxen zurücksetzen
        document.querySelectorAll('.safety-checkboxes input[type="checkbox"]').forEach(cb => {
            cb.checked = false;
        });
        document.getElementById('safety-accept-btn').disabled = true;
        
    } catch (error) {
        console.error('Logout Fehler:', error);
    }
}

// ============================================
// 12. HELPER FUNCTIONS
// ============================================

function showScreen(screenName) {
    const screens = document.querySelectorAll('.screen');
    screens.forEach(screen => {
        screen.classList.remove('active');
    });
    
    const targetScreen = document.getElementById(`${screenName}-screen`);
    if (targetScreen) {
        targetScreen.classList.add('active');
    }
}

function switchAuthForm(formType) {
    const loginForm = document.getElementById('login-form');
    const registerForm = document.getElementById('register-form');
    
    if (formType === 'login') {
        loginForm.classList.add('active');
        registerForm.classList.remove('active');
    } else {
        loginForm.classList.remove('active');
        registerForm.classList.add('active');
    }
    
    // Fehlermeldungen löschen
    hideError();
    hideSuccess();
}

function showError(message) {
    const errorDiv = document.getElementById('auth-error');
    errorDiv.textContent = message;
    errorDiv.style.display = 'block';
    
    // Nach 5 Sekunden ausblenden
    setTimeout(() => {
        hideError();
    }, 5000);
}

function hideError() {
    const errorDiv = document.getElementById('auth-error');
    errorDiv.style.display = 'none';
}

function showSuccess(message) {
    const successDiv = document.getElementById('auth-success');
    successDiv.textContent = message;
    successDiv.style.display = 'block';
    
    // Nach 5 Sekunden ausblenden
    setTimeout(() => {
        hideSuccess();
    }, 5000);
}

function hideSuccess() {
    const successDiv = document.getElementById('auth-success');
    successDiv.style.display = 'none';
}

function isValidEmail(email) {
    const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return re.test(email);
}

// ============================================
// 13. AUTH STATE LISTENER
// ============================================

supabase.auth.onAuthStateChange((event, session) => {
    console.log('Auth Event:', event);
    
    if (event === 'SIGNED_IN') {
        currentUser = session.user;
    } else if (event === 'SIGNED_OUT') {
        currentUser = null;
        currentProfile = null;
    }
});

// ============================================
// 14. ONLINE STATUS HEARTBEAT
// ============================================

// Alle 30 Sekunden Online-Status aktualisieren
setInterval(async () => {
    if (currentUser && currentProfile) {
        try {
            await supabase
                .from('profiles')
                .update({
                    last_active_at: new Date().toISOString()
                })
                .eq('id', currentUser.id);
        } catch (error) {
            console.error('Online-Status Update Fehler:', error);
        }
    }
}, 30000);

// ============================================
// 15. WINDOW EVENTS
// ============================================

// Beim Verlassen der Seite Online-Status auf false setzen
window.addEventListener('beforeunload', async () => {
    if (currentUser) {
        await supabase
            .from('profiles')
            .update({
                online_status: false,
                zuletzt_online: new Date().toISOString()
            })
            .eq('id', currentUser.id);
    }
});

// ============================================
// FERTIG! 🎉
// ============================================

console.log('✅ App JavaScript geladen!');
