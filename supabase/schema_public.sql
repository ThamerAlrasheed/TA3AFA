


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."care_code_status" AS ENUM (
    'active',
    'used',
    'expired'
);


ALTER TYPE "public"."care_code_status" OWNER TO "postgres";


CREATE TYPE "public"."dose_status_enum" AS ENUM (
    'pending',
    'taken',
    'skipped',
    'missed'
);


ALTER TYPE "public"."dose_status_enum" OWNER TO "postgres";


CREATE TYPE "public"."food_rule_enum" AS ENUM (
    'none',
    'beforeFood',
    'afterFood',
    'withFood'
);


ALTER TYPE "public"."food_rule_enum" OWNER TO "postgres";


CREATE TYPE "public"."user_role_enum" AS ENUM (
    'regular',
    'caregiver',
    'patient'
);


ALTER TYPE "public"."user_role_enum" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."appointments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "title" character varying(255) NOT NULL,
    "doctor_name" character varying(255),
    "appointment_time" timestamp with time zone NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "public"."appointments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."care_codes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" character varying(6) NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "caregiver_id" "uuid" NOT NULL,
    "status" "public"."care_code_status" DEFAULT 'active'::"public"."care_code_status",
    "expires_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "public"."care_codes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."caregiver_relations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "caregiver_id" "uuid" NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "can_patient_add_meds" boolean DEFAULT true NOT NULL,
    "notify_patient_meds" boolean DEFAULT true NOT NULL,
    "notify_patient_appointments" boolean DEFAULT true NOT NULL,
    "can_patient_manage_calendar" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."caregiver_relations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "device_token" character varying(255) NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "public"."device_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."medications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" character varying(255) NOT NULL,
    "active_ingredients" "text"[] DEFAULT '{}'::"text"[],
    "how_to_use" "text",
    "side_effects" "text"[] DEFAULT '{}'::"text"[],
    "contraindications" "text"[] DEFAULT '{}'::"text"[],
    "food_rule" "public"."food_rule_enum" DEFAULT 'none'::"public"."food_rule_enum",
    "min_interval_hours" integer,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "strengths" "text"[],
    "indications" "text"[],
    "interactions_to_avoid" "text"[],
    "common_side_effects" "text"[],
    "how_to_take" "text"[],
    "what_for" "text"[],
    "rxcui" "text",
    "last_updated" timestamp with time zone DEFAULT "now"(),
    "warnings" "text"[] DEFAULT '{}'::"text"[]
);


ALTER TABLE "public"."medications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."search_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "search_query" character varying(500) NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "public"."search_history" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_medications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "medication_id" "uuid",
    "name" character varying(255),
    "strength" character varying(100),
    "instructions" "text",
    "total_stock" integer DEFAULT 0,
    "reminder_enabled" boolean DEFAULT true,
    "food_rule" "public"."food_rule_enum" DEFAULT 'none'::"public"."food_rule_enum",
    "dosage_times" "text"[] DEFAULT '{}'::"text"[],
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "dosage" "text" DEFAULT ''::"text" NOT NULL,
    "frequency_per_day" integer DEFAULT 1 NOT NULL,
    "frequency_hours" integer,
    "start_date" "date",
    "end_date" "date",
    "notes" "text",
    "is_prn" boolean DEFAULT false NOT NULL,
    "is_manual_schedule" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."user_medications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "email" character varying(255),
    "role" "public"."user_role_enum" DEFAULT 'regular'::"public"."user_role_enum",
    "first_name" character varying(100) DEFAULT ''::character varying,
    "last_name" character varying(100) DEFAULT ''::character varying,
    "phone_number" character varying(20),
    "date_of_birth" "date",
    "allergies" "text"[] DEFAULT '{}'::"text"[],
    "conditions" "text"[] DEFAULT '{}'::"text"[],
    "breakfast_time" time without time zone DEFAULT '08:00:00'::time without time zone,
    "lunch_time" time without time zone DEFAULT '13:00:00'::time without time zone,
    "dinner_time" time without time zone DEFAULT '19:00:00'::time without time zone,
    "wakeup_time" time without time zone DEFAULT '07:00:00'::time without time zone,
    "bedtime" time without time zone DEFAULT '22:00:00'::time without time zone,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "public"."users" OWNER TO "postgres";


ALTER TABLE ONLY "public"."appointments"
    ADD CONSTRAINT "appointments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."care_codes"
    ADD CONSTRAINT "care_codes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."caregiver_relations"
    ADD CONSTRAINT "caregiver_relations_caregiver_id_patient_id_key" UNIQUE ("caregiver_id", "patient_id");



ALTER TABLE ONLY "public"."caregiver_relations"
    ADD CONSTRAINT "caregiver_relations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_sessions"
    ADD CONSTRAINT "device_sessions_device_token_key" UNIQUE ("device_token");



ALTER TABLE ONLY "public"."device_sessions"
    ADD CONSTRAINT "device_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."medications"
    ADD CONSTRAINT "medications_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."medications"
    ADD CONSTRAINT "medications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."search_history"
    ADD CONSTRAINT "search_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_medications"
    ADD CONSTRAINT "user_medications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."appointments"
    ADD CONSTRAINT "appointments_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."care_codes"
    ADD CONSTRAINT "care_codes_caregiver_id_fkey" FOREIGN KEY ("caregiver_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."care_codes"
    ADD CONSTRAINT "care_codes_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."caregiver_relations"
    ADD CONSTRAINT "caregiver_relations_caregiver_id_fkey" FOREIGN KEY ("caregiver_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."caregiver_relations"
    ADD CONSTRAINT "caregiver_relations_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_sessions"
    ADD CONSTRAINT "device_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."search_history"
    ADD CONSTRAINT "search_history_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_medications"
    ADD CONSTRAINT "user_medications_medication_id_fkey" FOREIGN KEY ("medication_id") REFERENCES "public"."medications"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_medications"
    ADD CONSTRAINT "user_medications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Allow authenticated users to insert medications" ON "public"."medications" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Allow authenticated users to read medications" ON "public"."medications" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Allow individual insert" ON "public"."users" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Allow individual select" ON "public"."users" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "Allow individual update" ON "public"."users" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "User can manage their own meds" ON "public"."user_medications" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete own medications" ON "public"."user_medications" FOR DELETE TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can insert own medications" ON "public"."user_medications" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can read own medications" ON "public"."user_medications" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can update own medications" ON "public"."user_medications" FOR UPDATE TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "allow_anon_appointments" ON "public"."appointments" FOR SELECT TO "anon" USING (true);



CREATE POLICY "allow_anon_meds" ON "public"."user_medications" FOR SELECT TO "anon" USING (true);



CREATE POLICY "allow_anon_relations" ON "public"."caregiver_relations" FOR SELECT TO "anon" USING (true);



CREATE POLICY "anon_delete_appointments" ON "public"."appointments" FOR DELETE TO "anon" USING (true);



CREATE POLICY "anon_delete_user_meds" ON "public"."user_medications" FOR DELETE TO "anon" USING (true);



CREATE POLICY "anon_insert_appointments" ON "public"."appointments" FOR INSERT TO "anon" WITH CHECK (true);



CREATE POLICY "anon_insert_user_meds" ON "public"."user_medications" FOR INSERT TO "anon" WITH CHECK (true);



CREATE POLICY "anon_select_appointments" ON "public"."appointments" FOR SELECT TO "anon" USING (true);



CREATE POLICY "anon_select_relations" ON "public"."caregiver_relations" FOR SELECT TO "anon" USING (true);



CREATE POLICY "anon_select_user_meds" ON "public"."user_medications" FOR SELECT TO "anon" USING (true);



CREATE POLICY "anon_update_appointments" ON "public"."appointments" FOR UPDATE TO "anon" USING (true);



CREATE POLICY "anon_update_user_meds" ON "public"."user_medications" FOR UPDATE TO "anon" USING (true);



ALTER TABLE "public"."care_codes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "care_codes_select_caregiver" ON "public"."care_codes" FOR SELECT TO "authenticated" USING (("caregiver_id" = "auth"."uid"()));



ALTER TABLE "public"."caregiver_relations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "caregiver_select_own" ON "public"."caregiver_relations" FOR SELECT TO "authenticated" USING (("caregiver_id" = "auth"."uid"()));



CREATE POLICY "caregiver_update_own" ON "public"."caregiver_relations" FOR UPDATE TO "authenticated" USING (("caregiver_id" = "auth"."uid"())) WITH CHECK (("caregiver_id" = "auth"."uid"()));



ALTER TABLE "public"."device_sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."medications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "patient_select_own" ON "public"."caregiver_relations" FOR SELECT TO "authenticated" USING (("patient_id" = "auth"."uid"()));



ALTER TABLE "public"."search_history" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "search_history_insert_caregiver" ON "public"."search_history" FOR INSERT TO "authenticated" WITH CHECK (("user_id" IN ( SELECT "caregiver_relations"."patient_id"
   FROM "public"."caregiver_relations"
  WHERE ("caregiver_relations"."caregiver_id" = "auth"."uid"()))));



ALTER TABLE "public"."user_medications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "users_select_caregiver" ON "public"."users" FOR SELECT TO "authenticated" USING (("id" IN ( SELECT "caregiver_relations"."patient_id"
   FROM "public"."caregiver_relations"
  WHERE ("caregiver_relations"."caregiver_id" = "auth"."uid"()))));



CREATE POLICY "users_update_caregiver" ON "public"."users" FOR UPDATE TO "authenticated" USING (("id" IN ( SELECT "caregiver_relations"."patient_id"
   FROM "public"."caregiver_relations"
  WHERE ("caregiver_relations"."caregiver_id" = "auth"."uid"())))) WITH CHECK (("id" IN ( SELECT "caregiver_relations"."patient_id"
   FROM "public"."caregiver_relations"
  WHERE ("caregiver_relations"."caregiver_id" = "auth"."uid"()))));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "anon";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";



GRANT ALL ON TABLE "public"."appointments" TO "anon";
GRANT ALL ON TABLE "public"."appointments" TO "authenticated";
GRANT ALL ON TABLE "public"."appointments" TO "service_role";



GRANT ALL ON TABLE "public"."care_codes" TO "anon";
GRANT ALL ON TABLE "public"."care_codes" TO "authenticated";
GRANT ALL ON TABLE "public"."care_codes" TO "service_role";



GRANT ALL ON TABLE "public"."caregiver_relations" TO "anon";
GRANT ALL ON TABLE "public"."caregiver_relations" TO "authenticated";
GRANT ALL ON TABLE "public"."caregiver_relations" TO "service_role";



GRANT ALL ON TABLE "public"."device_sessions" TO "anon";
GRANT ALL ON TABLE "public"."device_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."device_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."medications" TO "anon";
GRANT ALL ON TABLE "public"."medications" TO "authenticated";
GRANT ALL ON TABLE "public"."medications" TO "service_role";



GRANT ALL ON TABLE "public"."search_history" TO "anon";
GRANT ALL ON TABLE "public"."search_history" TO "authenticated";
GRANT ALL ON TABLE "public"."search_history" TO "service_role";



GRANT ALL ON TABLE "public"."user_medications" TO "anon";
GRANT ALL ON TABLE "public"."user_medications" TO "authenticated";
GRANT ALL ON TABLE "public"."user_medications" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






