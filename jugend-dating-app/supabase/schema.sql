-- ============================================
-- JUGEND DATING APP - SUPABASE SCHEMA
-- DSGVO-konform | Jugendschutz | Moderation
-- ============================================

-- WICHTIG: Dieses Script in Supabase SQL Editor ausführen!

-- ============================================
-- 1. EXTENSIONS
-- ============================================

-- UUID Extension für eindeutige IDs
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- 2. ENUMS (Aufzählungstypen)
-- ============================================

-- Account Status
CREATE TYPE account_status AS ENUM (
    'active',           -- Aktiv
    'warned',           -- Verwarnt
    'restricted',       -- Eingeschränkt
    'banned',           -- Gebannt
    'deleted'           -- Gelöscht
);

-- User Rollen
CREATE TYPE user_role AS ENUM (
    'user',             -- Normaler User
    'parent',           -- Elternteil
    'moderator',        -- Moderator
    'admin',            -- Admin
    'owner'             -- Owner (du!)
);

-- Moderation Klassifizierung
CREATE TYPE moderation_classification AS ENUM (
    'harmlos',
    'grenzwertig',
    'regelverstoß',
    'kritisch'
);

-- Moderation Aktion
CREATE TYPE moderation_action AS ENUM (
    'allow',
    'warn',
    'block',
    'mute',
    'report',
    'ban'
);

-- Report Status
CREATE TYPE report_status AS ENUM (
    'pending',          -- Wartet auf Bearbeitung
    'reviewing',        -- Wird bearbeitet
    'resolved',         -- Gelöst
    'rejected',         -- Abgelehnt
    'appealed'          -- Widerspruch eingelegt
);

-- Call Status
CREATE TYPE call_status AS ENUM (
    'ringing',
    'active',
    'ended',
    'missed',
    'rejected'
);

-- ============================================
-- 3. HAUPTTABELLEN
-- ============================================

-- ----------------
-- 3.1 PROFILES (erweiterte User-Daten)
-- ----------------
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Basis-Info
    username TEXT UNIQUE NOT NULL CHECK (length(username) >= 3 AND length(username) <= 20),
    geburtsdatum DATE NOT NULL,
    bio TEXT CHECK (length(bio) <= 500),
    
    -- Eltern-Verifizierung
    eltern_email TEXT,
    verified_parent BOOLEAN DEFAULT false,
    parent_verified_at TIMESTAMP WITH TIME ZONE,
    
    -- Profilbild
    profilbild_url TEXT,
    profilbild_hash TEXT, -- Hash gegen Duplikate
    
    -- Interessen & Location
    interessen TEXT[], -- Array von Interessen
    bundesland TEXT,
    stadt TEXT,
    
    -- Datenschutz-Settings
    online_status_visible BOOLEAN DEFAULT true,
    gelesen_status_visible BOOLEAN DEFAULT true,
    schreibstatus_visible BOOLEAN DEFAULT true,
    
    -- Status & Aktivität
    online_status BOOLEAN DEFAULT false,
    zuletzt_online TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_active_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Moderation
    strikes INTEGER DEFAULT 0 CHECK (strikes >= 0),
    account_status account_status DEFAULT 'active',
    ban_reason TEXT,
    ban_until TIMESTAMP WITH TIME ZONE,
    
    -- Sicherheit
    last_ip TEXT,
    vpn_detected BOOLEAN DEFAULT false,
    
    -- Rolle
    role user_role DEFAULT 'user',
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT age_check CHECK (
        EXTRACT(YEAR FROM AGE(geburtsdatum)) >= 14 
        AND EXTRACT(YEAR FROM AGE(geburtsdatum)) <= 100
    ),
    CONSTRAINT parent_email_required CHECK (
        CASE 
            WHEN EXTRACT(YEAR FROM AGE(geburtsdatum)) < 16 
            THEN eltern_email IS NOT NULL 
            ELSE true 
        END
    )
);

-- Index für Performance
CREATE INDEX idx_profiles_username ON profiles(username);
CREATE INDEX idx_profiles_account_status ON profiles(account_status);
CREATE INDEX idx_profiles_role ON profiles(role);
CREATE INDEX idx_profiles_bundesland ON profiles(bundesland);

-- ----------------
-- 3.2 PROFILBILDER (zusätzliche Bilder für Swipe)
-- ----------------
CREATE TABLE profile_images (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    image_url TEXT NOT NULL,
    image_hash TEXT NOT NULL, -- Gegen Duplikate
    position INTEGER NOT NULL CHECK (position >= 1 AND position <= 6), -- Max 6 Bilder
    nsfw_checked BOOLEAN DEFAULT false,
    nsfw_score FLOAT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(user_id, position)
);

CREATE INDEX idx_profile_images_user ON profile_images(user_id);

-- ----------------
-- 3.3 SWIPES
-- ----------------
CREATE TABLE swipes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    target_user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    liked BOOLEAN NOT NULL, -- true = like, false = dislike
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(user_id, target_user_id)
);

CREATE INDEX idx_swipes_user ON swipes(user_id);
CREATE INDEX idx_swipes_target ON swipes(target_user_id);

-- ----------------
-- 3.4 MATCHES
-- ----------------
CREATE TABLE matches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user1_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    user2_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    matched_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT different_users CHECK (user1_id != user2_id),
    CONSTRAINT ordered_users CHECK (user1_id < user2_id), -- Verhindert Duplikate
    UNIQUE(user1_id, user2_id)
);

CREATE INDEX idx_matches_user1 ON matches(user1_id);
CREATE INDEX idx_matches_user2 ON matches(user2_id);

-- ----------------
-- 3.5 CHATS
-- ----------------
CREATE TABLE chats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user1_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    user2_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_message_at TIMESTAMP WITH TIME ZONE,
    
    CONSTRAINT different_users CHECK (user1_id != user2_id),
    CONSTRAINT ordered_users CHECK (user1_id < user2_id),
    UNIQUE(user1_id, user2_id)
);

CREATE INDEX idx_chats_user1 ON chats(user1_id);
CREATE INDEX idx_chats_user2 ON chats(user2_id);
CREATE INDEX idx_chats_last_message ON chats(last_message_at DESC);

-- ----------------
-- 3.6 NACHRICHTEN
-- ----------------
CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    
    -- Nachricht
    content TEXT NOT NULL CHECK (length(content) > 0 AND length(content) <= 5000),
    
    -- Moderation
    moderation_classification moderation_classification,
    moderation_score INTEGER CHECK (moderation_score >= 0 AND moderation_score <= 100),
    moderation_reason TEXT,
    blocked BOOLEAN DEFAULT false,
    
    -- Status
    gelesen BOOLEAN DEFAULT false,
    gelesen_at TIMESTAMP WITH TIME ZONE,
    geloescht_sender BOOLEAN DEFAULT false,
    geloescht_receiver BOOLEAN DEFAULT false,
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_messages_chat ON messages(chat_id, created_at DESC);
CREATE INDEX idx_messages_sender ON messages(sender_id);
CREATE INDEX idx_messages_unread ON messages(chat_id, gelesen) WHERE gelesen = false;

-- ----------------
-- 3.7 ANRUFE (Audio/Video)
-- ----------------
CREATE TABLE calls (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    caller_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    
    -- Call Info
    is_video BOOLEAN DEFAULT false,
    status call_status DEFAULT 'ringing',
    
    -- Timestamps
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    answered_at TIMESTAMP WITH TIME ZONE,
    ended_at TIMESTAMP WITH TIME ZONE,
    duration_seconds INTEGER,
    
    -- Moderation
    ended_by_mod BOOLEAN DEFAULT false,
    mod_id UUID REFERENCES profiles(id)
);

CREATE INDEX idx_calls_chat ON calls(chat_id);
CREATE INDEX idx_calls_caller ON calls(caller_id);
CREATE INDEX idx_calls_receiver ON calls(receiver_id);

-- ----------------
-- 3.8 REPORTS (Meldungen)
-- ----------------
CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Wer meldet wen
    reporter_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    reported_user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    
    -- Was wird gemeldet
    message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    chat_id UUID REFERENCES chats(id) ON DELETE SET NULL,
    
    -- Report Details
    reason TEXT NOT NULL CHECK (length(reason) >= 10),
    category TEXT NOT NULL, -- grooming, sexual, gewalt, drogen, selbstverletzung, belaestigung
    
    -- Status
    status report_status DEFAULT 'pending',
    
    -- Moderation
    assigned_to UUID REFERENCES profiles(id), -- Welcher Mod bearbeitet
    mod_notes TEXT,
    action_taken moderation_action,
    resolved_at TIMESTAMP WITH TIME ZONE,
    
    -- Widerspruch
    appeal_text TEXT,
    appealed_at TIMESTAMP WITH TIME ZONE,
    appeal_resolved_at TIMESTAMP WITH TIME ZONE,
    appeal_notes TEXT,
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_reports_reporter ON reports(reporter_id);
CREATE INDEX idx_reports_reported ON reports(reported_user_id);
CREATE INDEX idx_reports_status ON reports(status);
CREATE INDEX idx_reports_assigned ON reports(assigned_to);

-- ----------------
-- 3.9 MODERATION ACTIONS (Log)
-- ----------------
CREATE TABLE moderation_actions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Wer hat was gemacht
    mod_id UUID NOT NULL REFERENCES profiles(id),
    target_user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    
    -- Aktion
    action moderation_action NOT NULL,
    reason TEXT NOT NULL,
    
    -- Related
    report_id UUID REFERENCES reports(id) ON DELETE SET NULL,
    message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    
    -- Details
    duration_hours INTEGER, -- Bei temporären Bans
    strikes_added INTEGER DEFAULT 0,
    
    -- Undo
    undone BOOLEAN DEFAULT false,
    undone_by UUID REFERENCES profiles(id),
    undone_at TIMESTAMP WITH TIME ZONE,
    undo_reason TEXT,
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_mod_actions_mod ON moderation_actions(mod_id);
CREATE INDEX idx_mod_actions_target ON moderation_actions(target_user_id);
CREATE INDEX idx_mod_actions_created ON moderation_actions(created_at DESC);

-- ----------------
-- 3.10 NOTIFICATIONS (Benachrichtigungen)
-- ----------------
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    
    -- Notification Type
    type TEXT NOT NULL, -- message_deleted, warning, restriction, ban, report_update
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    
    -- Related
    related_report_id UUID REFERENCES reports(id) ON DELETE SET NULL,
    related_action_id UUID REFERENCES moderation_actions(id) ON DELETE SET NULL,
    
    -- Status
    gelesen BOOLEAN DEFAULT false,
    gelesen_at TIMESTAMP WITH TIME ZONE,
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_notifications_user ON notifications(user_id, gelesen);
CREATE INDEX idx_notifications_created ON notifications(created_at DESC);

-- ----------------
-- 3.11 BLOCKED WORDS (Wortfilter)
-- ----------------
CREATE TABLE blocked_words (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    word TEXT UNIQUE NOT NULL,
    pattern TEXT, -- Regex Pattern
    severity INTEGER DEFAULT 1 CHECK (severity >= 1 AND severity <= 5),
    category TEXT NOT NULL,
    active BOOLEAN DEFAULT true,
    added_by UUID REFERENCES profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_blocked_words_active ON blocked_words(active);

-- ----------------
-- 3.12 VPN BLACKLIST
-- ----------------
CREATE TABLE vpn_ips (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ip_address TEXT UNIQUE NOT NULL,
    reason TEXT,
    added_by UUID REFERENCES profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_vpn_ips_address ON vpn_ips(ip_address);

-- ----------------
-- 3.13 SICHERHEITSHINWEISE BESTÄTIGUNG
-- ----------------
CREATE TABLE safety_confirmations (
    user_id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
    confirmed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    ip_address TEXT,
    version INTEGER DEFAULT 1 -- Falls Hinweise sich ändern
);

-- ============================================
-- 4. FUNCTIONS (Hilfsfunktionen)
-- ============================================

-- ----------------
-- 4.1 Updated_at automatisch setzen
-- ----------------
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger für Tabellen mit updated_at
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_messages_updated_at BEFORE UPDATE ON messages
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_reports_updated_at BEFORE UPDATE ON reports
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ----------------
-- 4.2 Automatisch Chat erstellen bei Match
-- ----------------
CREATE OR REPLACE FUNCTION create_chat_on_match()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO chats (user1_id, user2_id)
    VALUES (NEW.user1_id, NEW.user2_id)
    ON CONFLICT DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_create_chat_on_match
    AFTER INSERT ON matches
    FOR EACH ROW EXECUTE FUNCTION create_chat_on_match();

-- ----------------
-- 4.3 Match erkennen bei Swipe
-- ----------------
CREATE OR REPLACE FUNCTION check_and_create_match()
RETURNS TRIGGER AS $$
DECLARE
    reverse_swipe_exists BOOLEAN;
BEGIN
    -- Nur wenn es ein Like war
    IF NEW.liked = true THEN
        -- Prüfe ob der andere User auch geliked hat
        SELECT EXISTS (
            SELECT 1 FROM swipes 
            WHERE user_id = NEW.target_user_id 
            AND target_user_id = NEW.user_id 
            AND liked = true
        ) INTO reverse_swipe_exists;
        
        -- Wenn ja, Match erstellen
        IF reverse_swipe_exists THEN
            INSERT INTO matches (user1_id, user2_id)
            VALUES (
                LEAST(NEW.user_id, NEW.target_user_id),
                GREATEST(NEW.user_id, NEW.target_user_id)
            )
            ON CONFLICT DO NOTHING;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_check_match
    AFTER INSERT ON swipes
    FOR EACH ROW EXECUTE FUNCTION check_and_create_match();

-- ----------------
-- 4.4 Last Message Timestamp aktualisieren
-- ----------------
CREATE OR REPLACE FUNCTION update_chat_last_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE chats 
    SET last_message_at = NEW.created_at
    WHERE id = NEW.chat_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_chat_timestamp
    AFTER INSERT ON messages
    FOR EACH ROW EXECUTE FUNCTION update_chat_last_message();

-- ----------------
-- 4.5 Owner automatisch setzen
-- ----------------
CREATE OR REPLACE FUNCTION set_owner_role()
RETURNS TRIGGER AS $$
BEGIN
    -- Wenn E-Mail = pajaziti.leon97080@gmail.com → Owner
    IF NEW.email = 'pajaziti.leon97080@gmail.com' THEN
        UPDATE profiles 
        SET role = 'owner'
        WHERE id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_owner
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION set_owner_role();

-- ============================================
-- 5. ROW LEVEL SECURITY (RLS)
-- ============================================

-- Aktiviere RLS für alle Tabellen
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE profile_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE swipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE calls ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE moderation_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE blocked_words ENABLE ROW LEVEL SECURITY;
ALTER TABLE vpn_ips ENABLE ROW LEVEL SECURITY;
ALTER TABLE safety_confirmations ENABLE ROW LEVEL SECURITY;

-- ----------------
-- 5.1 PROFILES Policies
-- ----------------

-- Jeder kann sein eigenes Profil lesen
CREATE POLICY "Users can view own profile"
    ON profiles FOR SELECT
    USING (auth.uid() = id);

-- Jeder kann andere Profile lesen (für Swipe)
CREATE POLICY "Users can view other profiles"
    ON profiles FOR SELECT
    USING (true);

-- Jeder kann sein eigenes Profil erstellen
CREATE POLICY "Users can insert own profile"
    ON profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

-- Jeder kann sein eigenes Profil updaten
CREATE POLICY "Users can update own profile"
    ON profiles FOR UPDATE
    USING (auth.uid() = id);

-- Mods/Admins/Owner können alle Profile sehen und ändern
CREATE POLICY "Mods can manage profiles"
    ON profiles FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
            AND role IN ('moderator', 'admin', 'owner')
        )
    );

-- ----------------
-- 5.2 MESSAGES Policies
-- ----------------

-- User können Nachrichten in ihren Chats lesen
CREATE POLICY "Users can view messages in their chats"
    ON messages FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM chats
            WHERE chats.id = messages.chat_id
            AND (chats.user1_id = auth.uid() OR chats.user2_id = auth.uid())
        )
    );

-- User können Nachrichten senden
CREATE POLICY "Users can send messages"
    ON messages FOR INSERT
    WITH CHECK (
        sender_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM chats
            WHERE chats.id = chat_id
            AND (chats.user1_id = auth.uid() OR chats.user2_id = auth.uid())
        )
    );

-- Mods können alle Nachrichten sehen
CREATE POLICY "Mods can view all messages"
    ON messages FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
            AND role IN ('moderator', 'admin', 'owner')
        )
    );

-- ----------------
-- 5.3 REPORTS Policies
-- ----------------

-- User können eigene Reports sehen
CREATE POLICY "Users can view own reports"
    ON reports FOR SELECT
    USING (reporter_id = auth.uid());

-- User können Reports erstellen
CREATE POLICY "Users can create reports"
    ON reports FOR INSERT
    WITH CHECK (reporter_id = auth.uid());

-- User können eigene Reports updaten (für Widerspruch)
CREATE POLICY "Users can appeal reports"
    ON reports FOR UPDATE
    USING (reporter_id = auth.uid());

-- Mods können alle Reports sehen und bearbeiten
CREATE POLICY "Mods can manage reports"
    ON reports FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
            AND role IN ('moderator', 'admin', 'owner')
        )
    );

-- ----------------
-- 5.4 NOTIFICATIONS Policies
-- ----------------

-- User können nur eigene Notifications sehen
CREATE POLICY "Users can view own notifications"
    ON notifications FOR SELECT
    USING (user_id = auth.uid());

-- User können eigene Notifications als gelesen markieren
CREATE POLICY "Users can mark notifications as read"
    ON notifications FOR UPDATE
    USING (user_id = auth.uid());

-- System/Mods können Notifications erstellen
CREATE POLICY "Mods can create notifications"
    ON notifications FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
            AND role IN ('moderator', 'admin', 'owner')
        )
    );

-- ----------------
-- 5.5 MODERATION_ACTIONS Policies
-- ----------------

-- Nur Mods/Admins/Owner können Moderation Actions sehen und erstellen
CREATE POLICY "Mods can manage moderation actions"
    ON moderation_actions FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
            AND role IN ('moderator', 'admin', 'owner')
        )
    );

-- ============================================
-- 6. SEED DATA (Erste Daten)
-- ============================================

-- Beispiel-Wortfilter
INSERT INTO blocked_words (word, severity, category) VALUES
('fick', 3, 'sexual'),
('sex', 2, 'sexual'),
('nackt', 2, 'sexual'),
('bild', 1, 'grenzwertig'), -- Kontext-abhängig
('treffen', 1, 'grooming'),
('adresse', 2, 'grooming'),
('schule', 2, 'grooming'),
('telefon', 2, 'grooming'),
('whatsapp', 2, 'platform_switch'),
('snapchat', 2, 'platform_switch'),
('instagram', 2, 'platform_switch');

-- ============================================
-- FERTIG! 🎉
-- ============================================

-- Nächste Schritte:
-- 1. Dieses Script in Supabase SQL Editor kopieren
-- 2. Ausführen
-- 3. Prüfen ob alle Tabellen da sind
-- 4. Supabase URL + Keys kopieren für Frontend
