CREATE TABLE `auth_tokens` (
	`id` text PRIMARY KEY NOT NULL,
	`purpose` text DEFAULT 'magic_link' NOT NULL,
	`email` text NOT NULL,
	`token_hash` text NOT NULL,
	`expires_at` integer NOT NULL,
	`consumed_at` integer,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `auth_tokens_token_hash_unique` ON `auth_tokens` (`token_hash`);--> statement-breakpoint
CREATE INDEX `auth_tokens_email_idx` ON `auth_tokens` (`email`);--> statement-breakpoint
CREATE TABLE `calendar_targets` (
	`id` text PRIMARY KEY NOT NULL,
	`member_id` text NOT NULL,
	`name` text NOT NULL,
	`method` text NOT NULL,
	`provider_hint` text,
	`external_account_id` text,
	`address_or_url` text NOT NULL,
	`external_calendar_id` text,
	`alert_minutes` text,
	`active` integer DEFAULT true NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`member_id`) REFERENCES `family_members`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`external_account_id`) REFERENCES `external_accounts`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE INDEX `calendar_targets_member_idx` ON `calendar_targets` (`member_id`);--> statement-breakpoint
CREATE TABLE `classification_rules` (
	`id` text PRIMARY KEY NOT NULL,
	`family_id` text NOT NULL,
	`feed_id` text,
	`priority` integer DEFAULT 100 NOT NULL,
	`match_field` text NOT NULL,
	`match_op` text NOT NULL,
	`match_value` text NOT NULL,
	`effect` text NOT NULL,
	`produces_types` text,
	`default_attendance` text,
	`shift_to_time` text,
	`default_owner_member_id` text,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`family_id`) REFERENCES `families`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`feed_id`) REFERENCES `feeds`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`default_owner_member_id`) REFERENCES `family_members`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE INDEX `classification_rules_family_idx` ON `classification_rules` (`family_id`);--> statement-breakpoint
CREATE INDEX `classification_rules_feed_idx` ON `classification_rules` (`feed_id`);--> statement-breakpoint
CREATE TABLE `deliveries` (
	`id` text PRIMARY KEY NOT NULL,
	`task_id` text NOT NULL,
	`calendar_target_id` text NOT NULL,
	`method` text NOT NULL,
	`status` text DEFAULT 'pending' NOT NULL,
	`external_ref` text,
	`ical_uid` text,
	`sequence` integer DEFAULT 0 NOT NULL,
	`payload_hash` text,
	`rsvp_status` text DEFAULT 'none' NOT NULL,
	`sent_at` integer,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`task_id`) REFERENCES `tasks`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`calendar_target_id`) REFERENCES `calendar_targets`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `deliveries_task_idx` ON `deliveries` (`task_id`);--> statement-breakpoint
CREATE INDEX `deliveries_ical_uid_idx` ON `deliveries` (`ical_uid`);--> statement-breakpoint
CREATE TABLE `external_accounts` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`kind` text NOT NULL,
	`name` text NOT NULL,
	`server_url` text,
	`username` text,
	`credentials_ref` text,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`credentials_ref`) REFERENCES `secrets`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE INDEX `external_accounts_user_idx` ON `external_accounts` (`user_id`);--> statement-breakpoint
CREATE TABLE `families` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `family_member_feeds` (
	`id` text PRIMARY KEY NOT NULL,
	`family_id` text NOT NULL,
	`feed_id` text NOT NULL,
	`family_member_id` text NOT NULL,
	`weekday_mask` integer,
	`day_start` text,
	`day_end` text,
	`duration_minutes` integer,
	`location` text,
	`generates_types` text,
	`default_attendance` text,
	`active` integer DEFAULT true NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`family_id`) REFERENCES `families`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`feed_id`) REFERENCES `feeds`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`family_member_id`) REFERENCES `family_members`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `fmf_feed_member_uq` ON `family_member_feeds` (`feed_id`,`family_member_id`);--> statement-breakpoint
CREATE INDEX `fmf_family_idx` ON `family_member_feeds` (`family_id`);--> statement-breakpoint
CREATE TABLE `family_members` (
	`id` text PRIMARY KEY NOT NULL,
	`family_id` text NOT NULL,
	`user_id` text,
	`relation_name` text NOT NULL,
	`is_caretaker` integer DEFAULT false NOT NULL,
	`is_admin` integer DEFAULT false NOT NULL,
	`requires_caretaker` integer DEFAULT false NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`family_id`) REFERENCES `families`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE INDEX `family_members_family_idx` ON `family_members` (`family_id`);--> statement-breakpoint
CREATE INDEX `family_members_user_idx` ON `family_members` (`user_id`);--> statement-breakpoint
CREATE TABLE `feeds` (
	`id` text PRIMARY KEY NOT NULL,
	`family_id` text NOT NULL,
	`kind` text DEFAULT 'ics' NOT NULL,
	`url` text,
	`external_account_id` text,
	`source_calendar_id` text,
	`source_calendar_name` text,
	`mode` text NOT NULL,
	`timezone` text,
	`refresh_minutes` integer DEFAULT 360 NOT NULL,
	`etag` text,
	`last_synced_at` integer,
	`last_refresh_requested_at` integer,
	`status` text DEFAULT 'active' NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`family_id`) REFERENCES `families`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`external_account_id`) REFERENCES `external_accounts`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE INDEX `feeds_family_idx` ON `feeds` (`family_id`);--> statement-breakpoint
CREATE TABLE `identities` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`provider` text NOT NULL,
	`provider_ref` text NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `identities_provider_ref_uq` ON `identities` (`provider`,`provider_ref`);--> statement-breakpoint
CREATE INDEX `identities_user_idx` ON `identities` (`user_id`);--> statement-breakpoint
CREATE TABLE `invites` (
	`id` text PRIMARY KEY NOT NULL,
	`type` text NOT NULL,
	`family_id` text,
	`issued_by_member_id` text,
	`member_id` text,
	`email` text,
	`token` text NOT NULL,
	`grant_is_caretaker` integer DEFAULT true NOT NULL,
	`grant_is_admin` integer DEFAULT false NOT NULL,
	`status` text DEFAULT 'pending' NOT NULL,
	`expires_at` integer,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`family_id`) REFERENCES `families`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`issued_by_member_id`) REFERENCES `family_members`(`id`) ON UPDATE no action ON DELETE set null,
	FOREIGN KEY (`member_id`) REFERENCES `family_members`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `invites_token_unique` ON `invites` (`token`);--> statement-breakpoint
CREATE INDEX `invites_status_idx` ON `invites` (`status`);--> statement-breakpoint
CREATE TABLE `ownership_rules` (
	`id` text PRIMARY KEY NOT NULL,
	`family_id` text NOT NULL,
	`filter` text,
	`weekday_mask` integer,
	`owner_member_id` text NOT NULL,
	`active` integer DEFAULT true NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`family_id`) REFERENCES `families`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`owner_member_id`) REFERENCES `family_members`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `ownership_rules_family_idx` ON `ownership_rules` (`family_id`);--> statement-breakpoint
CREATE TABLE `secrets` (
	`id` text PRIMARY KEY NOT NULL,
	`family_id` text,
	`ciphertext` text NOT NULL,
	`iv` text NOT NULL,
	`wrapped_dek` text NOT NULL,
	`key_version` integer DEFAULT 1 NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`family_id`) REFERENCES `families`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `sessions` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`token_hash` text NOT NULL,
	`expires_at` integer NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `sessions_token_hash_unique` ON `sessions` (`token_hash`);--> statement-breakpoint
CREATE INDEX `sessions_user_idx` ON `sessions` (`user_id`);--> statement-breakpoint
CREATE TABLE `source_events` (
	`id` text PRIMARY KEY NOT NULL,
	`feed_id` text NOT NULL,
	`family_id` text NOT NULL,
	`ical_uid` text NOT NULL,
	`recurrence_id` text,
	`dtstart` integer NOT NULL,
	`dtend` integer,
	`all_day` integer DEFAULT false NOT NULL,
	`summary` text,
	`location` text,
	`raw` text,
	`content_hash` text NOT NULL,
	`tasks_built_hash` text,
	`dismissed_at` integer,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`feed_id`) REFERENCES `feeds`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`family_id`) REFERENCES `families`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `source_events_occurrence_uq` ON `source_events` (`feed_id`,`ical_uid`,`recurrence_id`);--> statement-breakpoint
CREATE INDEX `source_events_feed_idx` ON `source_events` (`feed_id`);--> statement-breakpoint
CREATE TABLE `tasks` (
	`id` text PRIMARY KEY NOT NULL,
	`family_id` text NOT NULL,
	`feed_id` text,
	`source_event_id` text,
	`family_member_id` text NOT NULL,
	`type` text NOT NULL,
	`attendance_requirement` text,
	`dtstart` integer NOT NULL,
	`dtend` integer,
	`location` text,
	`status` text DEFAULT 'unowned' NOT NULL,
	`owner_member_id` text,
	`created_via` text NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`family_id`) REFERENCES `families`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`feed_id`) REFERENCES `feeds`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`source_event_id`) REFERENCES `source_events`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`family_member_id`) REFERENCES `family_members`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`owner_member_id`) REFERENCES `family_members`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE INDEX `tasks_family_status_idx` ON `tasks` (`family_id`,`status`);--> statement-breakpoint
CREATE INDEX `tasks_source_event_idx` ON `tasks` (`source_event_id`);--> statement-breakpoint
CREATE TABLE `users` (
	`id` text PRIMARY KEY NOT NULL,
	`username` text NOT NULL,
	`display_name` text NOT NULL,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `users_username_unique` ON `users` (`username`);