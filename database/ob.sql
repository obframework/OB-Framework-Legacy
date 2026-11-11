-- OB Framework - banco inicial publico higienizado
-- Mantem a estrutura e configuracoes reutilizaveis. Nao contem contas, personagens, membros de organizacoes, inventarios, logs ou identificadores reais.
-- Revise o nome do banco e faca backup antes de importar.

-- --------------------------------------------------------
-- Servidor:                     SERVIDOR_LOCAL
-- Versão do servidor:           11.8.6-MariaDB-5ubuntu0.1 from Ubuntu - -- Please help get to 10k stars at https://github.com/MariaDB/Server
-- OS do Servidor:               debian-linux-gnu
-- HeidiSQL Versão:              12.21.0.7344
-- --------------------------------------------------------

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET NAMES utf8 */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;


-- Copiando estrutura do banco de dados para orcore
CREATE DATABASE IF NOT EXISTS `orcore` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci */;
USE `orcore`;

-- Copiando estrutura para tabela orcore.ob_admin_account_archives
CREATE TABLE IF NOT EXISTS `ob_admin_account_archives` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `player_id` bigint(20) unsigned NOT NULL,
  `license` varchar(80) NOT NULL,
  `archived_by_user_id` bigint(20) unsigned NOT NULL,
  `reason` varchar(255) NOT NULL,
  `snapshot` longtext NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ob_admin_archive_player` (`player_id`,`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=21 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_admin_account_archives omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_admin_account_bans
CREATE TABLE IF NOT EXISTS `ob_admin_account_bans` (
  `license` varchar(80) NOT NULL,
  `player_id` bigint(20) unsigned DEFAULT NULL,
  `reason` varchar(255) NOT NULL,
  `banned_by_user_id` bigint(20) unsigned NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `expires_at` datetime DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `revoked_at` datetime DEFAULT NULL,
  `revoked_by_user_id` bigint(20) unsigned DEFAULT NULL,
  PRIMARY KEY (`license`),
  KEY `idx_ob_admin_bans_player` (`player_id`),
  KEY `idx_ob_admin_bans_active` (`active`,`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_admin_account_bans omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_admin_audit
CREATE TABLE IF NOT EXISTS `ob_admin_audit` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `admin_license` varchar(80) DEFAULT NULL,
  `admin_source` smallint(5) unsigned DEFAULT NULL,
  `admin_user_id` bigint(20) unsigned DEFAULT NULL,
  `target_license` varchar(80) DEFAULT NULL,
  `target_source` smallint(5) unsigned DEFAULT NULL,
  `target_user_id` bigint(20) unsigned DEFAULT NULL,
  `action` varchar(40) NOT NULL,
  `details` varchar(255) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_or_admin_audit_created_at` (`created_at`),
  KEY `idx_or_admin_audit_target_license` (`target_license`)
) ENGINE=InnoDB AUTO_INCREMENT=1329 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_admin_audit omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_admin_characters
CREATE TABLE IF NOT EXISTS `ob_admin_characters` (
  `user_id` bigint(20) unsigned NOT NULL,
  `role` varchar(32) NOT NULL DEFAULT 'admin',
  `granted_by_user_id` bigint(20) unsigned DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`user_id`),
  KEY `idx_or_admin_characters_granted_by` (`granted_by_user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_admin_characters omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_admin_destructive_audit
CREATE TABLE IF NOT EXISTS `ob_admin_destructive_audit` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `actor_user_id` bigint(20) unsigned NOT NULL,
  `action` varchar(64) NOT NULL,
  `target_player_id` bigint(20) unsigned DEFAULT NULL,
  `target_user_id` bigint(20) unsigned DEFAULT NULL,
  `details` longtext DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ob_admin_destructive_actor` (`actor_user_id`,`created_at`),
  KEY `idx_ob_admin_destructive_target` (`target_player_id`,`target_user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_admin_destructive_audit omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_ballistic_archive
CREATE TABLE IF NOT EXISTS `ob_ballistic_archive` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ballistic_signature` varchar(96) DEFAULT NULL,
  `ammo_type` varchar(32) DEFAULT NULL,
  `weapon_item` varchar(64) DEFAULT NULL,
  `fingerprint_code` varchar(64) DEFAULT NULL,
  `evidence_data` longtext NOT NULL,
  `analyzed_by` varchar(64) NOT NULL,
  `created_at` datetime NOT NULL,
  `expires_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ob_ballistic_signature` (`ballistic_signature`),
  KEY `idx_ob_ballistic_expires` (`expires_at`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_ballistic_archive omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_bank_accounts
CREATE TABLE IF NOT EXISTS `ob_bank_accounts` (
  `user_id` int(11) NOT NULL,
  `balance` bigint(20) NOT NULL DEFAULT 0,
  `card_issued` tinyint(1) NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_bank_accounts omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_bank_cards
CREATE TABLE IF NOT EXISTS `ob_bank_cards` (
  `card_number` char(16) NOT NULL,
  `owner_user_id` int(11) NOT NULL,
  `pin_hash` char(64) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `issued_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `cancelled_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`card_number`),
  KEY `idx_bank_cards_owner` (`owner_user_id`,`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_bank_cards omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_bank_transactions
CREATE TABLE IF NOT EXISTS `ob_bank_transactions` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `kind` varchar(24) NOT NULL,
  `amount` bigint(20) NOT NULL,
  `description` varchar(120) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_bank_transactions_user` (`user_id`,`id`)
) ENGINE=InnoDB AUTO_INCREMENT=134 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_bank_transactions omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_bus_progress
CREATE TABLE IF NOT EXISTS `ob_bus_progress` (
  `user_id` bigint(20) unsigned NOT NULL,
  `xp` int(11) NOT NULL DEFAULT 0,
  `level` int(11) NOT NULL DEFAULT 1,
  `rides` int(11) NOT NULL DEFAULT 0,
  `total_earned` int(11) NOT NULL DEFAULT 0,
  `best_fare` int(11) NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_or_bus_progress_character` FOREIGN KEY (`user_id`) REFERENCES `ob_characters` (`user_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_bus_progress omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_carshop_vehicles
CREATE TABLE IF NOT EXISTS `ob_carshop_vehicles` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `shop_id` int(10) unsigned NOT NULL,
  `model` varchar(64) NOT NULL,
  `label` varchar(80) NOT NULL,
  `category` varchar(48) NOT NULL DEFAULT 'Outros',
  `price` int(10) unsigned NOT NULL,
  `stock` int(10) unsigned NOT NULL DEFAULT 0,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_ob_carshop_vehicle_model` (`shop_id`,`model`),
  CONSTRAINT `fk_ob_carshop_vehicles_shop` FOREIGN KEY (`shop_id`) REFERENCES `ob_carshops` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=42 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Copiando dados para a tabela orcore.ob_carshop_vehicles: ~41 rows (aproximadamente)
INSERT INTO `ob_carshop_vehicles` (`id`, `shop_id`, `model`, `label`, `category`, `price`, `stock`, `enabled`, `created_at`, `updated_at`) VALUES
	(1, 1, 'blista', 'Dinka Blista', 'Compacto', 18000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(2, 1, 'panto', 'Benefactor Panto', 'Compacto', 14500, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(3, 1, 'asea', 'Declasse Asea', 'Sedan', 22000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(4, 1, 'sultan', 'Karin Sultan', 'Esportivo', 85000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(5, 1, 'kuruma', 'Karin Kuruma', 'Esportivo', 112000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(6, 1, 'buffalo', 'Bravado Buffalo', 'Esportivo', 72000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(7, 1, 'futo', 'Karin Futo', 'Compacto', 38000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(8, 1, 'dominator', 'Vapid Dominator', 'Muscle', 76000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(9, 1, 'elegy2', 'Annis Elegy RH8', 'Esportivo', 98000, 9, 1, '2026-08-23 05:44:24', '2026-08-23 06:42:10'),
	(10, 1, 'jester', 'Dinka Jester', 'Esportivo', 145000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(11, 1, 'comet2', 'Pfister Comet', 'Esportivo', 125000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(12, 1, 'ninef', 'Obey 9F', 'Esportivo', 138000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(13, 1, 'massacro', 'Dewbauchee Massacro', 'Esportivo', 155000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(14, 1, 'carbonizzare', 'Grotti Carbonizzare', 'Esportivo', 170000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(15, 1, 'feltzer2', 'Benefactor Feltzer', 'Esportivo', 149000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(16, 1, 'turismo2', 'Grotti Turismo R', 'Super', 310000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(17, 1, 'adder', 'Truffade Adder', 'Super', 600000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(18, 1, 'entityxf', 'Overflod Entity XF', 'Super', 520000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(19, 1, 'zentorno', 'Pegassi Zentorno', 'Super', 490000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(20, 1, 'osiris', 'Pegassi Osiris', 'Super', 650000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(21, 1, 'xa21', 'Ocelot XA-21', 'Super', 710000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(22, 1, 'reaper', 'Pegassi Reaper', 'Super', 680000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(23, 1, 'pfister811', 'Pfister 811', 'Super', 750000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(24, 1, 'neon', 'Pfister Neon', 'Esportivo', 260000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(25, 1, 'baller', 'Gallivanter Baller', 'SUV', 110000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(26, 1, 'granger', 'Declasse Granger', 'SUV', 95000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(27, 1, 'dubsta', 'Benefactor Dubsta', 'SUV', 135000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(28, 1, 'mesa', 'Canis Mesa', 'SUV', 76000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(29, 1, 'bison', 'Bravado Bison', 'Utilitario', 70000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(30, 1, 'rumpo', 'Bravado Rumpo', 'Utilitario', 65000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(31, 1, 'bf400', 'Nagasaki BF400', 'Moto', 45000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(32, 1, 'bati', 'Pegassi Bati 801', 'Moto', 68000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(33, 1, 'akuma', 'Dinka Akuma', 'Moto', 57000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(34, 1, 'daemon', 'Western Daemon', 'Moto', 42000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(35, 1, 'double', 'Dinka Double-T', 'Moto', 64000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(36, 1, 'faggio', 'Pegassi Faggio', 'Moto', 9000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(37, 1, 'hakuchou', 'Shitzu Hakuchou', 'Moto', 90000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(38, 1, 'innovation', 'LCC Innovation', 'Moto', 88000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(39, 1, 'nemesis', 'Principe Nemesis', 'Moto', 30000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(40, 1, 'pcj', 'Shitzu PCJ 600', 'Moto', 26000, 10, 1, '2026-08-23 05:44:24', '2026-08-23 05:44:24'),
	(41, 1, 'driftyosemite', 'Drift Yosemite', 'Drift', 35000, 10, 1, '2026-08-28 01:40:19', '2026-08-28 01:40:19');

-- Copiando estrutura para tabela orcore.ob_carshops
CREATE TABLE IF NOT EXISTS `ob_carshops` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `label` varchar(80) NOT NULL,
  `shop_type` enum('public','player') NOT NULL DEFAULT 'public',
  `owner_user_id` bigint(20) unsigned DEFAULT NULL,
  `access_json` text NOT NULL,
  `delivery_json` text DEFAULT NULL,
  `test_json` text DEFAULT NULL,
  `blip_sprite` smallint(5) unsigned NOT NULL DEFAULT 225,
  `blip_color` smallint(5) unsigned NOT NULL DEFAULT 3,
  `blip_scale` decimal(4,2) NOT NULL DEFAULT 0.82,
  `blip_short_range` tinyint(1) NOT NULL DEFAULT 1,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ob_carshops_owner` (`owner_user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Copiando dados para a tabela orcore.ob_carshops: ~0 rows (aproximadamente)
INSERT INTO `ob_carshops` (`id`, `label`, `shop_type`, `owner_user_id`, `access_json`, `delivery_json`, `test_json`, `blip_sprite`, `blip_color`, `blip_scale`, `blip_short_range`, `active`, `created_at`, `updated_at`) VALUES
	(1, 'Premium Motors', 'public', NULL, '{"x":-56.4219,"y":-1099.1156,"z":26.4224,"w":30.7028}', '{"x":-47.8838,"y":-1097.4756,"z":26.4223,"w":70.0000}', '{"x":-888.5062,"y":-3207.2808,"z":13.9464,"w":55.2832}', 225, 3, 0.82, 1, 1, '2026-08-23 05:44:23', '2026-08-23 06:03:18');

-- Copiando estrutura para tabela orcore.ob_character_appearances
CREATE TABLE IF NOT EXISTS `ob_character_appearances` (
  `user_id` bigint(20) unsigned NOT NULL,
  `model` varchar(64) NOT NULL,
  `appearance` mediumtext NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_or_character_appearances_character` FOREIGN KEY (`user_id`) REFERENCES `ob_characters` (`user_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_character_appearances omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_character_outfits
CREATE TABLE IF NOT EXISTS `ob_character_outfits` (
  `user_id` bigint(20) unsigned NOT NULL,
  `slot` tinyint(3) unsigned NOT NULL,
  `label` varchar(32) NOT NULL,
  `appearance` mediumtext NOT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`,`slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_character_outfits omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_character_slots
CREATE TABLE IF NOT EXISTS `ob_character_slots` (
  `license` varchar(80) NOT NULL,
  `unlocked_slots` tinyint(3) unsigned NOT NULL DEFAULT 1,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`license`),
  CONSTRAINT `fk_or_character_slots_player` FOREIGN KEY (`license`) REFERENCES `ob_players` (`license`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_character_slots omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_characters
CREATE TABLE IF NOT EXISTS `ob_characters` (
  `user_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `license` varchar(80) NOT NULL,
  `slot` int(10) unsigned NOT NULL,
  `firstname` varchar(32) NOT NULL,
  `lastname` varchar(32) NOT NULL,
  `birthdate` date NOT NULL,
  `gender` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `nationality` varchar(48) NOT NULL DEFAULT 'Brasileiro',
  `last_position` longtext DEFAULT NULL,
  `metadata` longtext DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `last_played_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  `blocked_at` timestamp NULL DEFAULT NULL,
  `blocked_reason` varchar(255) DEFAULT NULL,
  `blocked_by_user_id` bigint(20) unsigned DEFAULT NULL,
  PRIMARY KEY (`user_id`),
  UNIQUE KEY `uq_or_characters_license_slot` (`license`,`slot`),
  KEY `idx_or_characters_license` (`license`),
  CONSTRAINT `fk_or_characters_player` FOREIGN KEY (`license`) REFERENCES `ob_players` (`license`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=27 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_characters omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_chemical_traces
CREATE TABLE IF NOT EXISTS `ob_chemical_traces` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` varchar(64) NOT NULL,
  `trace_kind` varchar(16) NOT NULL,
  `substance` varchar(64) NOT NULL,
  `origin` varchar(64) NOT NULL,
  `detected_at` datetime NOT NULL,
  `expires_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ob_chemical_user` (`user_id`,`expires_at`),
  KEY `idx_ob_chemical_expires` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_chemical_traces omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_crafting_blueprints
CREATE TABLE IF NOT EXISTS `ob_crafting_blueprints` (
  `user_id` bigint(20) unsigned NOT NULL,
  `recipe_id` varchar(64) NOT NULL,
  `granted_by` bigint(20) unsigned DEFAULT NULL,
  `granted_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`user_id`,`recipe_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Copiando dados para a tabela orcore.ob_crafting_blueprints: ~0 rows (aproximadamente)

-- Copiando estrutura para tabela orcore.ob_crafting_profiles
CREATE TABLE IF NOT EXISTS `ob_crafting_profiles` (
  `user_id` bigint(20) unsigned NOT NULL,
  `xp` int(10) unsigned NOT NULL DEFAULT 0,
  `crafts` int(10) unsigned NOT NULL DEFAULT 0,
  `successes` int(10) unsigned NOT NULL DEFAULT 0,
  `failures` int(10) unsigned NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_crafting_profiles omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_disconnect_logs
CREATE TABLE IF NOT EXISTS `ob_disconnect_logs` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) unsigned DEFAULT NULL,
  `session_id` int(10) unsigned NOT NULL,
  `player_name` varchar(128) NOT NULL,
  `reason` varchar(512) NOT NULL,
  `resource_name` varchar(128) NOT NULL,
  `client_drop_reason` int(10) unsigned NOT NULL DEFAULT 0,
  `drop_reason_label` varchar(64) NOT NULL,
  `classification` varchar(64) NOT NULL,
  `connected_seconds` int(10) unsigned DEFAULT NULL,
  `last_snapshot_age_ms` int(10) unsigned DEFAULT NULL,
  `snapshot` mediumtext DEFAULT NULL,
  `crash_report_code` varchar(64) DEFAULT NULL,
  `created_at` timestamp(3) NOT NULL DEFAULT current_timestamp(3),
  PRIMARY KEY (`id`),
  KEY `idx_ob_disconnect_logs_user_time` (`user_id`,`created_at`),
  KEY `idx_ob_disconnect_logs_time` (`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=198 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_disconnect_logs omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_doorlock_doors
CREATE TABLE IF NOT EXISTS `ob_doorlock_doors` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `group_id` int(10) unsigned NOT NULL,
  `label` varchar(80) NOT NULL,
  `door_type` enum('single','double') NOT NULL DEFAULT 'single',
  `leaves` longtext NOT NULL,
  `locked` tinyint(3) unsigned NOT NULL DEFAULT 1,
  `enabled` tinyint(3) unsigned NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ob_doorlock_group` (`group_id`)
) ENGINE=InnoDB AUTO_INCREMENT=12 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Copiando dados para a tabela orcore.ob_doorlock_doors: ~6 rows (aproximadamente)
INSERT INTO `ob_doorlock_doors` (`id`, `group_id`, `label`, `door_type`, `leaves`, `locked`, `enabled`, `created_at`, `updated_at`) VALUES
	(6, 1, 'entrada', 'double', '[{"model":185711165,"offset":{"y":-0.00018310546875,"z":0,"heading":0.0,"x":-0.65109252929687},"name":"v_ilev_ph_gendoor005","center":{"y":-989.4456176757813,"z":30.83930206298828,"heading":0.0,"x":445.3568420410156},"coords":{"y":-989.4454345703124,"z":30.83930206298828,"heading":0.0,"x":446.0079345703125}},{"model":185711165,"offset":{"y":-0.00018320378148,"z":0,"heading":0.0,"x":-0.65109252929687},"name":"v_ilev_ph_gendoor005","center":{"y":-989.4452514648438,"z":30.83930206298828,"heading":0.0,"x":444.0588684082031},"coords":{"y":-989.4454345703124,"z":30.83930206298828,"heading":179.99998474121098,"x":443.40777587890627}}]', 1, 1, '2026-10-27 14:53:30', '2026-10-29 01:30:34'),
	(7, 1, 'saida', 'double', '[{"name":"v_ilev_rc_door2","model":-2023754432,"coords":{"y":-1014.4520263671876,"x":469.9678955078125,"heading":179.99998474121098,"z":26.5362319946289},"center":{"y":-1014.4518432617188,"x":469.3179016113281,"heading":0.0,"z":26.5362319946289},"offset":{"y":-0.00018300731608,"x":0.64999389648437,"heading":0.0,"z":0}},{"name":"v_ilev_rc_door2","model":-2023754432,"coords":{"y":-1014.4520263671876,"x":467.37164306640627,"heading":0.0,"z":26.5362319946289},"center":{"y":-1014.4522094726564,"x":468.0216369628906,"heading":0.0,"z":26.5362319946289},"offset":{"y":-0.00018310546875,"x":0.64999389648437,"heading":0.0,"z":0}}]', 1, 1, '2026-10-27 15:01:31', '2026-10-27 15:10:07'),
	(8, 1, 'sela1', 'single', '[{"name":"v_ilev_ph_cellgate","model":631614199,"coords":{"y":-994.4085693359376,"x":461.8065185546875,"heading":270,"z":25.06442642211914},"center":{"y":-993.758544921875,"x":461.8065185546875,"heading":0.0,"z":25.06442642211914},"offset":{"y":4.9075477903670626e-8,"x":-0.6500244140625,"heading":0.0,"z":0}}]', 1, 1, '2026-10-27 15:02:06', '2026-10-27 15:02:56'),
	(9, 1, 'sela2', 'single', '[{"name":"v_ilev_ph_cellgate","model":631614199,"coords":{"y":-997.6583251953124,"x":461.8064880371094,"heading":89.99999237060547,"z":25.06442642211914},"center":{"y":-998.308349609375,"x":461.8064880371094,"heading":0.0,"z":25.06442642211914},"offset":{"y":-4.9075477903670626e-8,"x":-0.6500244140625,"heading":0.0,"z":0}}]', 1, 1, '2026-10-27 15:02:23', '2026-10-27 15:02:23'),
	(10, 1, 'sela3', 'single', '[{"name":"v_ilev_ph_cellgate","model":631614199,"coords":{"y":-1001.301513671875,"x":461.8065185546875,"heading":89.99999237060547,"z":25.06442642211914},"center":{"y":-1001.9515380859376,"x":461.8065185546875,"heading":0.0,"z":25.06442642211914},"offset":{"y":-4.9075477903670626e-8,"x":-0.6500244140625,"heading":0.0,"z":0}}]', 1, 1, '2026-10-27 15:02:42', '2026-10-27 15:02:42'),
	(11, 1, 'heliponto', 'single', '[{"name":"v_ilev_gtdoor02","model":-340230128,"coords":{"y":-984.6780395507813,"x":464.361328125,"heading":89.99999237060547,"z":43.83443450927734},"center":{"y":-984.0280151367188,"x":464.3617858886719,"heading":0.0,"z":43.83443450927734},"offset":{"y":-0.00045771460281,"x":0.6500244140625,"heading":0.0,"z":0}}]', 1, 1, '2026-10-27 15:04:14', '2026-10-27 15:04:14');

-- Copiando estrutura para tabela orcore.ob_doorlock_groups
CREATE TABLE IF NOT EXISTS `ob_doorlock_groups` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `label` varchar(80) NOT NULL,
  `permissions` longtext NOT NULL,
  `public_access` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `require_duty` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `interaction_distance` decimal(5,2) NOT NULL DEFAULT 2.00,
  `auto_lock_seconds` int(10) unsigned NOT NULL DEFAULT 0,
  `default_locked` tinyint(3) unsigned NOT NULL DEFAULT 1,
  `enabled` tinyint(3) unsigned NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Copiando dados para a tabela orcore.ob_doorlock_groups: ~0 rows (aproximadamente)
INSERT INTO `ob_doorlock_groups` (`id`, `label`, `permissions`, `public_access`, `require_duty`, `interaction_distance`, `auto_lock_seconds`, `default_locked`, `enabled`, `created_at`, `updated_at`) VALUES
	(1, 'Police', '["police"]', 0, 1, 1.00, 0, 1, 1, '2026-10-27 04:48:43', '2026-10-27 15:09:48');

-- Copiando estrutura para tabela orcore.ob_drug_plants
CREATE TABLE IF NOT EXISTS `ob_drug_plants` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `owner_user_id` bigint(20) unsigned NOT NULL,
  `plant_type` varchar(24) DEFAULT NULL,
  `x` double NOT NULL,
  `y` double NOT NULL,
  `z` double NOT NULL,
  `heading` float NOT NULL DEFAULT 0,
  `growth` float NOT NULL DEFAULT 0,
  `water` float NOT NULL DEFAULT 0,
  `nutrients` float NOT NULL DEFAULT 0,
  `health` float NOT NULL DEFAULT 100,
  `last_update` bigint(20) unsigned NOT NULL,
  `pot_uses_remaining` tinyint(3) unsigned NOT NULL DEFAULT 5,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ob_drug_plants_owner` (`owner_user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_drug_plants omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_economy_accounts
CREATE TABLE IF NOT EXISTS `ob_economy_accounts` (
  `account_key` varchar(64) NOT NULL,
  `label` varchar(100) NOT NULL,
  `kind` varchar(32) NOT NULL DEFAULT 'treasury',
  `balance` bigint(20) NOT NULL DEFAULT 0,
  `initial_balance` bigint(20) NOT NULL DEFAULT 0,
  `allow_negative` tinyint(1) NOT NULL DEFAULT 0,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`account_key`),
  KEY `idx_ob_economy_accounts_kind` (`kind`,`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_economy_accounts omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_economy_ledger
CREATE TABLE IF NOT EXISTS `ob_economy_ledger` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `account_key` varchar(64) NOT NULL,
  `direction` varchar(16) NOT NULL,
  `amount` bigint(20) NOT NULL,
  `balance_before` bigint(20) NOT NULL,
  `balance_after` bigint(20) NOT NULL,
  `category` varchar(64) NOT NULL,
  `status` varchar(24) NOT NULL,
  `actor_user_id` int(11) DEFAULT NULL,
  `target_user_id` int(11) DEFAULT NULL,
  `source_resource` varchar(64) NOT NULL,
  `description` varchar(255) NOT NULL DEFAULT '',
  `metadata` longtext DEFAULT NULL,
  `parent_ledger_id` bigint(20) unsigned DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ob_economy_ledger_account` (`account_key`,`id`),
  KEY `idx_ob_economy_ledger_category` (`category`,`id`),
  KEY `idx_ob_economy_ledger_target` (`target_user_id`,`id`),
  KEY `idx_ob_economy_ledger_parent` (`parent_ledger_id`),
  CONSTRAINT `fk_ob_economy_ledger_account` FOREIGN KEY (`account_key`) REFERENCES `ob_economy_accounts` (`account_key`)
) ENGINE=InnoDB AUTO_INCREMENT=67 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_economy_ledger omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_electrician_progress
CREATE TABLE IF NOT EXISTS `ob_electrician_progress` (
  `user_id` bigint(20) unsigned NOT NULL,
  `xp` int(11) NOT NULL DEFAULT 0,
  `level` int(11) NOT NULL DEFAULT 1,
  `repairs` int(11) NOT NULL DEFAULT 0,
  `total_earned` int(11) NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_ob_electrician_character` FOREIGN KEY (`user_id`) REFERENCES `ob_characters` (`user_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_electrician_progress omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_feedback_reports
CREATE TABLE IF NOT EXISTS `ob_feedback_reports` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) unsigned NOT NULL,
  `player_name` varchar(96) NOT NULL,
  `character_name` varchar(128) DEFAULT NULL,
  `description` text NOT NULL,
  `screenshot_url` varchar(1024) DEFAULT NULL,
  `status` varchar(16) NOT NULL DEFAULT 'open',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ob_feedback_created` (`created_at`),
  KEY `idx_ob_feedback_user` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_feedback_reports omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_fingerprint_registry
CREATE TABLE IF NOT EXISTS `ob_fingerprint_registry` (
  `fingerprint_code` varchar(64) NOT NULL,
  `user_id` varchar(64) NOT NULL,
  `person_name` varchar(100) NOT NULL,
  `registered_by` varchar(64) NOT NULL,
  `registered_at` datetime NOT NULL,
  PRIMARY KEY (`fingerprint_code`),
  KEY `idx_ob_fingerprint_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_fingerprint_registry omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_fingerprint_traces
CREATE TABLE IF NOT EXISTS `ob_fingerprint_traces` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `fingerprint_code` varchar(64) NOT NULL,
  `trace_type` varchar(24) NOT NULL,
  `reference_id` varchar(96) NOT NULL,
  `details` longtext NOT NULL,
  `recorded_at` datetime NOT NULL,
  `expires_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_ob_fingerprint_trace` (`fingerprint_code`,`trace_type`,`reference_id`),
  KEY `idx_ob_fingerprint_trace_expires` (`expires_at`)
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_fingerprint_traces omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_fiscal_business_accounts
CREATE TABLE IF NOT EXISTS `ob_fiscal_business_accounts` (
  `shop_id` varchar(64) NOT NULL,
  `owner_user_id` bigint(20) unsigned NOT NULL,
  `owner_name` varchar(100) DEFAULT NULL,
  `shop_label` varchar(100) NOT NULL,
  `unreported_balance` bigint(20) unsigned NOT NULL DEFAULT 0,
  `risk_score` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `last_declaration_at` datetime DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`shop_id`),
  KEY `idx_ob_fiscal_account_owner` (`owner_user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_fiscal_business_accounts omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_fiscal_declarations
CREATE TABLE IF NOT EXISTS `ob_fiscal_declarations` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `shop_id` varchar(64) NOT NULL,
  `owner_user_id` bigint(20) unsigned NOT NULL,
  `owner_name` varchar(100) DEFAULT NULL,
  `shop_label` varchar(100) NOT NULL,
  `gross_amount` bigint(20) unsigned NOT NULL,
  `tax_percent` tinyint(3) unsigned NOT NULL,
  `tax_amount` bigint(20) unsigned NOT NULL,
  `net_amount` bigint(20) unsigned NOT NULL,
  `real_sales_7d` bigint(20) unsigned NOT NULL DEFAULT 0,
  `risk_score` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `risk_reasons` longtext DEFAULT NULL,
  `status` enum('reserving','crediting','credited','completed','flagged','failed','review') NOT NULL DEFAULT 'reserving',
  `credit_token` varchar(96) DEFAULT NULL,
  `treasury_ledger_id` bigint(20) unsigned DEFAULT NULL,
  `integrity_note` varchar(255) DEFAULT NULL,
  `police_status` enum('new','reviewing','cleared','escalated') NOT NULL DEFAULT 'new',
  `police_notes` varchar(500) DEFAULT NULL,
  `reviewed_by` bigint(20) unsigned DEFAULT NULL,
  `reviewed_at` datetime DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `settled_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ob_fiscal_declaration_shop` (`shop_id`,`created_at`),
  KEY `idx_ob_fiscal_declaration_risk` (`risk_score`,`police_status`,`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_fiscal_declarations omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_fiscal_deposits
CREATE TABLE IF NOT EXISTS `ob_fiscal_deposits` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `shop_id` varchar(64) NOT NULL,
  `user_id` bigint(20) unsigned NOT NULL,
  `amount` bigint(20) unsigned NOT NULL,
  `balance_before` bigint(20) unsigned NOT NULL,
  `balance_after` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ob_fiscal_deposit_shop` (`shop_id`,`created_at`),
  KEY `idx_ob_fiscal_deposit_user` (`user_id`,`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_fiscal_deposits omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_fiscal_payroll
CREATE TABLE IF NOT EXISTS `ob_fiscal_payroll` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `shop_id` varchar(64) NOT NULL,
  `owner_user_id` bigint(20) unsigned NOT NULL,
  `owner_name` varchar(100) DEFAULT NULL,
  `amount` bigint(20) unsigned NOT NULL,
  `status` enum('paying','paid','failed','review') NOT NULL DEFAULT 'paying',
  `debit_token` varchar(96) DEFAULT NULL,
  `integrity_note` varchar(255) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `paid_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ob_fiscal_payroll_shop` (`shop_id`,`created_at`),
  KEY `idx_ob_fiscal_payroll_owner` (`owner_user_id`,`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_fiscal_payroll omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_forensic_reports
CREATE TABLE IF NOT EXISTS `ob_forensic_reports` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `analyst_user_id` varchar(64) NOT NULL,
  `report_type` varchar(40) NOT NULL,
  `weapon_item` varchar(64) DEFAULT NULL,
  `serial` varchar(64) DEFAULT NULL,
  `report_data` longtext NOT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ob_forensic_serial` (`serial`),
  KEY `idx_ob_forensic_analyst` (`analyst_user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=12 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_forensic_reports omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_garage_definitions
CREATE TABLE IF NOT EXISTS `ob_garage_definitions` (
  `garage_id` varchar(48) NOT NULL,
  `label` varchar(80) NOT NULL,
  `data` longtext NOT NULL,
  `created_by` bigint(20) unsigned NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`garage_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Copiando dados para a tabela orcore.ob_garage_definitions: ~6 rows (aproximadamente)
INSERT INTO `ob_garage_definitions` (`garage_id`, `label`, `data`, `created_by`, `created_at`, `updated_at`) VALUES
	('central', 'Garagem', '{"size":{"y":4,"x":4,"z":3},"id":"central","coords":{"y":-810.12,"x":215.82,"z":30.73},"storeSize":{"y":7,"x":7,"z":3},"spawns":[{"y":-808.7898,"x":219.4893,"w":250.129,"z":30.6885}],"spawnClearRadius":1.75,"blipEnabled":true,"taxExempt":false,"label":"Garagem","storeCoords":{"y":-800.13,"x":228.72,"z":30.57},"vehicleType":"personal","vehicles":[],"blip":{"color":3,"label":"Garagem","scale":0.82,"sprite":357},"storeDistance":16}', 0, '2026-09-06 04:14:00', '2026-09-14 05:52:06'),
	('free_faggio', 'Veiculos Gratuitos', '{"taxExempt":true,"id":"free_faggio","storeSize":{"y":7,"x":7,"z":3},"storeDistance":16,"label":"Veiculos Gratuitos","coords":{"y":-2734.415,"x":-1031.4021,"z":20.1693},"size":{"y":4,"x":4,"z":3},"vehicleType":"free","spawns":[{"y":-2730.4858,"x":-1031.2535,"w":237.4752,"z":20.127}],"sharedGroup":"faggiofree","spawnClearRadius":1.75,"storeCoords":{"y":-2734.415,"x":-1031.4021,"z":20.1693},"blipEnabled":true,"vehicles":[{"taxExempt":true,"price":0,"label":"Pegassi Faggio","model":"faggio","departmentPrice":0}],"blip":{"sprite":357,"label":"Veiculos Gratuitos","color":2,"scale":0.82}}', 0, '2026-09-06 04:14:00', '2026-10-01 15:52:28'),
	('free_faggio2', 'Veiculos Gratuitos', '{"taxExempt":true,"id":"free_faggio2","storeSize":{"y":7,"x":7,"z":3},"storeDistance":16,"label":"Veiculos Gratuitos","coords":{"y":-876.5421752929688,"x":56.44929504394531,"z":30.65875625610351},"size":{"y":4,"x":4,"z":3},"vehicleType":"free","spawns":[{"y":-866.9046020507813,"x":60.3420524597168,"w":343.3765563964844,"z":30.55446243286132},{"y":-865.9743041992188,"x":56.78185272216797,"w":345.2351379394531,"z":30.55971145629882}],"sharedGroup":"faggiofree","spawnClearRadius":1.75,"storeCoords":{"y":-876.5421752929688,"x":56.44929504394531,"z":30.65875625610351},"blipEnabled":true,"vehicles":[{"taxExempt":true,"price":0,"label":"Pegassi Faggio","model":"faggio","departmentPrice":0}],"blip":{"sprite":357,"label":"Veiculos Gratuitos","color":2,"scale":0.82}}', 0, '2026-09-16 11:51:49', '2026-10-01 15:52:46'),
	('lixeiro', 'Garagem do Lixeiro', '{"size":{"y":4,"x":4,"z":3},"id":"lixeiro","coords":{"y":-1513.8527,"x":-317.406,"z":27.5908},"storeSize":{"y":7,"x":7,"z":3},"spawns":[{"y":-1516.0194,"x":-319.0338,"w":179.7358,"z":27.5655}],"spawnClearRadius":1.75,"blipEnabled":true,"taxExempt":false,"label":"Garagem do Lixeiro","storeCoords":{"y":-1513.8527,"x":-317.406,"z":27.5908},"vehicleType":"personal","vehicles":[],"blip":{"color":3,"label":"Garagem","scale":0.82,"sprite":357},"storeDistance":16}', 0, '2026-09-06 04:14:00', '2026-09-14 05:52:29'),
	('pillboxhill', 'garagem', '{"size":{"y":4,"x":4,"z":3},"id":"pillboxhill","coords":{"y":-874.9612426757813,"x":-349.1209106445313,"z":31.31801795959472},"storeSize":{"y":7,"x":7,"z":3},"spawns":[{"y":-875.2549438476563,"x":-343.5251159667969,"w":172.762451171875,"z":31.07143020629882},{"y":-876.657470703125,"x":-340.1697998046875,"w":170.57269287109376,"z":31.07143020629882}],"spawnClearRadius":1.75,"blipEnabled":true,"taxExempt":false,"label":"garagem","storeCoords":{"y":-874.9612426757813,"x":-349.1209106445313,"z":31.31801795959472},"vehicleType":"personal","vehicles":[],"blip":{"color":3,"label":"Garagem","scale":0.82,"sprite":357},"storeDistance":16}', 0, '2026-09-10 09:01:45', '2026-09-14 05:52:12'),
	('police_service', 'Garagem da Policia', '{"spawnClearRadius":1.75,"blipEnabled":false,"label":"Garagem da Policia","size":{"z":3.0,"y":4.0,"x":4.0},"storeSize":{"z":3.0,"y":7.0,"x":7.0},"taxExempt":false,"storeCoords":{"z":28.64,"y":-1024.25,"x":445.67},"vehicles":[{"model":"police3","departmentPrice":25000,"price":100,"taxExempt":false,"label":"Police Interceptor"},{"model":"policeb2","departmentPrice":25000,"price":100,"taxExempt":false,"label":"Police Motorcycle"},{"model":"polgauntlet","departmentPrice":25000,"price":100,"taxExempt":false,"label":"Police Gauntlet"},{"model":"polignus","departmentPrice":25000,"price":100,"taxExempt":false,"label":"Police Ignus"},{"model":"polterminus","departmentPrice":25000,"price":100,"taxExempt":false,"label":"Police Terminus"}],"storeDistance":16.0,"coords":{"z":28.43,"y":-1017.42,"x":454.64},"economyAccount":"police","taxRatePercent":5.0,"vehicleType":"service","access":{"requireDuty":true,"permission":"police"},"spawns":[{"w":90.0,"z":27.76,"y":-1018.3,"x":438.42}],"id":"police_service"}', 0, '2026-09-06 04:14:00', '2026-09-06 04:14:00');

-- Copiando estrutura para tabela orcore.ob_garbage_progress
CREATE TABLE IF NOT EXISTS `ob_garbage_progress` (
  `user_id` bigint(20) unsigned NOT NULL,
  `xp` int(11) NOT NULL DEFAULT 0,
  `level` int(11) NOT NULL DEFAULT 1,
  `routes_completed` int(11) NOT NULL DEFAULT 0,
  `total_earned` int(11) NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_or_garbage_progress_character` FOREIGN KEY (`user_id`) REFERENCES `ob_characters` (`user_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_garbage_progress omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_health_injuries
CREATE TABLE IF NOT EXISTS `ob_health_injuries` (
  `user_id` bigint(20) unsigned NOT NULL,
  `injuries` longtext NOT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_health_injuries omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_inventories
CREATE TABLE IF NOT EXISTS `ob_inventories` (
  `owner_type` varchar(32) NOT NULL,
  `owner_id` varchar(96) NOT NULL,
  `items` mediumtext NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`owner_type`,`owner_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_inventories omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_inventory_shop_businesses
CREATE TABLE IF NOT EXISTS `ob_inventory_shop_businesses` (
  `shop_id` varchar(64) NOT NULL,
  `owner_user_id` bigint(20) unsigned DEFAULT NULL,
  `owner_name` varchar(100) DEFAULT NULL,
  `custom_name` varchar(80) NOT NULL,
  `balance` bigint(20) unsigned NOT NULL DEFAULT 0,
  `total_sales` bigint(20) unsigned NOT NULL DEFAULT 0,
  `total_tax` bigint(20) unsigned NOT NULL DEFAULT 0,
  `purchase_price` bigint(20) unsigned NOT NULL DEFAULT 0,
  `purchased_at` datetime DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`shop_id`),
  KEY `idx_ob_shop_owner` (`owner_user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_inventory_shop_businesses omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_inventory_shop_fiscal_entries
CREATE TABLE IF NOT EXISTS `ob_inventory_shop_fiscal_entries` (
  `token` varchar(96) NOT NULL,
  `shop_id` varchar(64) NOT NULL,
  `owner_user_id` bigint(20) unsigned NOT NULL,
  `direction` enum('credit','debit') NOT NULL,
  `amount` bigint(20) unsigned NOT NULL,
  `metadata` longtext DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`token`),
  KEY `idx_ob_shop_fiscal_shop` (`shop_id`,`created_at`),
  KEY `idx_ob_shop_fiscal_owner` (`owner_user_id`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_inventory_shop_fiscal_entries omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_inventory_shop_groups
CREATE TABLE IF NOT EXISTS `ob_inventory_shop_groups` (
  `id` varchar(64) NOT NULL,
  `data` longtext NOT NULL,
  `deleted` tinyint(4) NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Copiando dados para a tabela orcore.ob_inventory_shop_groups: ~7 rows (aproximadamente)
INSERT INTO `ob_inventory_shop_groups` (`id`, `data`, `deleted`, `updated_at`) VALUES
	('ambulance', '{"purchasable":false,"items":[{"name":"bandage","departmentPrice":35,"wholesalePrice":0,"initialStock":50,"price":0,"maxStock":500},{"name":"medkit","departmentPrice":120,"wholesalePrice":0,"initialStock":50,"price":0,"maxStock":500},{"name":"defibrillator","departmentPrice":2500,"wholesalePrice":0,"initialStock":50,"price":0,"maxStock":500},{"name":"medicalbag","departmentPrice":350,"wholesalePrice":0,"initialStock":50,"price":0,"maxStock":500},{"name":"analgesic","departmentPrice":25,"wholesalePrice":0,"initialStock":50,"price":0,"maxStock":500},{"name":"tweezers","departmentPrice":120,"wholesalePrice":0,"initialStock":50,"price":0,"maxStock":500},{"name":"burncream","departmentPrice":80,"wholesalePrice":0,"initialStock":50,"price":0,"maxStock":500},{"name":"suturekit","departmentPrice":180,"wholesalePrice":0,"initialStock":50,"price":0,"maxStock":500},{"name":"icepack","departmentPrice":40,"wholesalePrice":0,"initialStock":50,"price":0,"maxStock":500},{"name":"stretcher","departmentPrice":1200,"wholesalePrice":0,"initialStock":50,"price":0,"maxStock":500},{"name":"emstablet","departmentPrice":850,"wholesalePrice":0,"initialStock":50,"price":0,"maxStock":500}],"maxStock":500,"purchasePrice":2500000,"id":"ambulance","initialStock":50,"label":"Suprimentos hospitalares","requireDuty":true,"currency":"money","departmentAccount":"ambulance","ped":"s_m_m_paramedic_01","permission":"ambulance"}', 0, '2026-10-23 19:49:36'),
	('convenience', '{"purchasable":true,"label":"Conveniência","currency":"money","items":[{"departmentPrice":0,"initialStock":50,"price":10,"maxStock":500,"name":"water","wholesalePrice":0},{"departmentPrice":0,"initialStock":50,"price":18,"maxStock":500,"name":"bread","wholesalePrice":0},{"departmentPrice":0,"initialStock":50,"price":45,"maxStock":500,"name":"bandage","wholesalePrice":0},{"departmentPrice":0,"initialStock":50,"price":150,"maxStock":500,"name":"medkit","wholesalePrice":0},{"departmentPrice":0,"initialStock":50,"price":400,"maxStock":500,"name":"coxinha_molho","wholesalePrice":0}],"id":"convenience","blip":{"color":2,"sprite":59,"scale":0.72},"category":"convenience","purchasePrice":2500000,"requireDuty":false,"maxStock":500,"initialStock":50,"ped":"mp_m_shopkeep_01"}', 0, '2026-10-24 04:34:31'),
	('digital_den', '{"purchasable":false,"items":[{"name":"phone","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":2000,"maxStock":500},{"name":"powerbank","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":500,"maxStock":500}],"blip":{"sprite":355,"scale":0.72,"color":50},"purchasePrice":2500000,"id":"digital_den","maxStock":500,"initialStock":50,"label":"Digital Den","requireDuty":false,"currency":"money","ped":"a_m_y_business_03"}', 0, '2026-10-23 19:49:37'),
	('ilegal_shop', '{"purchasable":false,"items":[{"name":"lockpick","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":150,"maxStock":500},{"name":"advanced_lockpick","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":400,"maxStock":500},{"name":"weapon_pistol","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":4500,"maxStock":500},{"name":"weapon_microsmg","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":25000,"maxStock":500},{"name":"ammo_pistol","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":10,"maxStock":500},{"name":"ammo_smg","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":40,"maxStock":500}],"blip":{"sprite":303,"scale":0.72,"color":76},"purchasePrice":2500000,"id":"ilegal_shop","maxStock":500,"initialStock":50,"label":"Loja Ilegal","requireDuty":false,"currency":"black_money","ped":"g_f_m_undeadmage"}', 0, '2026-10-23 19:49:37'),
	('mechanic_products', '{"purchasable":false,"items":[{"name":"hydraulic_jack","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":1500,"maxStock":500},{"name":"tyre_normal","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":250,"maxStock":500},{"name":"weapon_wrench","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":100,"maxStock":500},{"name":"vehicle_oil","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":180,"maxStock":500},{"name":"brake_pads","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":320,"maxStock":500},{"name":"spark_plugs","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":220,"maxStock":500},{"name":"fuel_drain_kit","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":650,"maxStock":500},{"name":"odometer_reader","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":950,"maxStock":500},{"name":"repairkit","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":850,"maxStock":500},{"name":"advancedrepairkit","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":1650,"maxStock":500}],"blip":{"sprite":544,"scale":0.72,"color":24},"purchasePrice":2500000,"id":"mechanic_products","maxStock":500,"initialStock":50,"label":"Produtos Mecanica","requireDuty":false,"currency":"money","ped":"s_m_y_xmech_01"}', 0, '2026-10-23 19:49:38'),
	('police', '{"requireDuty":true,"purchaseLimit":100,"items":[{"maxStock":500,"initialStock":50,"maxPurchase":0,"departmentPrice":500,"price":500,"wholesalePrice":0,"name":"weapon_pistol50"},{"maxStock":500,"initialStock":50,"maxPurchase":0,"departmentPrice":1500,"price":1500,"wholesalePrice":0,"name":"weapon_assaultsmg"},{"maxStock":500,"initialStock":50,"maxPurchase":0,"departmentPrice":3500,"price":3500,"wholesalePrice":0,"name":"weapon_advancedrifle"},{"maxStock":500,"initialStock":50,"maxPurchase":0,"departmentPrice":1500,"price":1500,"wholesalePrice":0,"name":"weapon_stungun"},{"maxStock":500,"initialStock":50,"maxPurchase":0,"departmentPrice":250,"price":250,"wholesalePrice":0,"name":"handcuffs"},{"maxStock":500,"initialStock":50,"maxPurchase":0,"departmentPrice":350,"price":350,"wholesalePrice":0,"name":"weapon_component_flashlight"},{"maxStock":500,"initialStock":50,"maxPurchase":0,"departmentPrice":350,"price":350,"wholesalePrice":0,"name":"weapon_component_suppressor"},{"maxStock":500,"initialStock":50,"maxPurchase":0,"departmentPrice":350,"price":350,"wholesalePrice":0,"name":"weapon_component_grip"},{"maxStock":500,"initialStock":50,"maxPurchase":0,"departmentPrice":350,"price":350,"wholesalePrice":0,"name":"weapon_component_scope_small"},{"maxStock":500,"initialStock":50,"maxPurchase":0,"departmentPrice":100,"price":100,"wholesalePrice":0,"name":"ammo_pistol"},{"maxStock":500,"initialStock":50,"maxPurchase":0,"departmentPrice":100,"price":100,"wholesalePrice":0,"name":"ammo_smg"},{"maxStock":500,"initialStock":50,"maxPurchase":0,"departmentPrice":100,"price":100,"wholesalePrice":0,"name":"ammo_rifle"},{"maxStock":500,"initialStock":50,"maxPurchase":20,"departmentPrice":10,"price":10,"wholesalePrice":0,"name":"empty_evidence_bag"},{"maxStock":500,"initialStock":50,"maxPurchase":1,"departmentPrice":750,"price":750,"wholesalePrice":0,"name":"forensic_kit"},{"maxStock":500,"initialStock":50,"maxPurchase":10,"departmentPrice":90,"price":90,"wholesalePrice":0,"name":"residue_test_kit"},{"maxStock":500,"initialStock":50,"maxPurchase":10,"departmentPrice":120,"price":120,"wholesalePrice":0,"name":"chemical_test_kit"},{"maxStock":500,"initialStock":50,"maxPurchase":10,"departmentPrice":80,"price":80,"wholesalePrice":0,"name":"fingerprint_collection_kit"},{"maxStock":500,"initialStock":50,"maxPurchase":1,"departmentPrice":250,"price":250,"wholesalePrice":0,"name":"forensic_magnifier"},{"maxStock":500,"initialStock":50,"maxPurchase":3,"departmentPrice":250,"price":250,"wholesalePrice":0,"name":"police_vest"}],"initialStock":50,"maxStock":500,"currency":"money","departmentAccount":"police","permission":"police","ped":"s_m_y_cop_01","purchasePrice":2500000,"label":"Suprimentos policiais","purchasable":false,"category":"general","id":"police"}', 0, '2026-11-01 09:00:49'),
	('produtos', '{"purchasable":false,"items":[{"name":"empty_bag","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":150,"maxStock":500},{"name":"watering_can","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":500,"maxStock":500},{"name":"plant_pot","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":500,"maxStock":500},{"name":"weed_seed","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":10,"maxStock":500},{"name":"coca_seed","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":10,"maxStock":500},{"name":"plant_fertilizer","departmentPrice":0,"wholesalePrice":0,"initialStock":50,"price":50,"maxStock":500}],"blip":{"sprite":140,"scale":0.8,"color":25},"purchasePrice":2500000,"id":"produtos","maxStock":500,"initialStock":50,"label":"Produtos","requireDuty":false,"currency":"money","ped":"cs_josh"}', 0, '2026-10-23 19:49:38');

-- Copiando estrutura para tabela orcore.ob_inventory_shop_locations
CREATE TABLE IF NOT EXISTS `ob_inventory_shop_locations` (
  `id` varchar(64) NOT NULL,
  `data` longtext NOT NULL,
  `deleted` tinyint(4) NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Copiando dados para a tabela orcore.ob_inventory_shop_locations: ~11 rows (aproximadamente)
INSERT INTO `ob_inventory_shop_locations` (`id`, `data`, `deleted`, `updated_at`) VALUES
	('__groups_v2', '{}', 1, '2026-10-23 19:49:38'),
	('__seed_v1', '{}', 1, '2026-09-06 04:14:01'),
	('ambulance_pillbox', '{"purchasable":false,"purchasePrice":0,"id":"ambulance_pillbox","group":"ambulance","label":"Suprimentos hospitalares","coords":{"z":43.2918,"w":68.0,"x":315.5516,"y":-598.6013}}', 0, '2026-10-23 19:49:36'),
	('ammunation_pillbox', '{"label":"Loja ilegal","coords":{"w":260.4,"x":456.0432739257813,"y":-1079.125,"z":29.3915901184082},"requireDuty":false,"blip":{"color":76,"scale":0.72,"sprite":303},"ped":"mp_m_shopkeep_01","currency":"money","items":[{"departmentPrice":0,"price":100,"name":"lockpick"},{"departmentPrice":0,"price":200,"name":"advanced_lockpick"},{"departmentPrice":0,"price":10000,"name":"weapon_pistol"},{"departmentPrice":0,"price":40000,"name":"weapon_microsmg"},{"departmentPrice":0,"price":10,"name":"ammo_pistol"},{"departmentPrice":0,"price":40,"name":"ammo_smg"}],"id":"ammunation_pillbox","group":""}', 1, '2026-09-09 05:06:15'),
	('convenience_grove', '{"purchasable":true,"id":"convenience_grove","purchasePrice":0,"dropoff":{"x":26.14631843566894,"y":-1346.751953125,"z":29.49701881408691,"w":92.95497131347656},"group":"convenience","label":"Conveniência","manager":{"x":33.85696411132812,"y":-1343.344482421875,"z":29.49701881408691,"w":84.70550537109375},"truckStop":{"x":15.92008876800537,"y":-1352.125732421875,"z":29.32847023010254,"w":4.48799037933349},"npcSpawn":{"x":271.8378601074219,"y":-1403.60498046875,"z":29.77264595031738,"w":140.5291748046875},"purchaseLimit":0,"coords":{"x":24.40269088745117,"y":-1345.978759765625,"z":29.49701690673828,"w":268.6485900878906},"npcWalkPoint":{"x":29.16489219665527,"y":-1350.2039794921876,"z":29.33171463012695,"w":3.92436432838439}}', 0, '2026-10-27 00:16:19'),
	('convenience_little_seoul', '{"group":"convenience","purchasable":true,"label":"Conveniência","id":"convenience_little_seoul","manager":{"w":178.64002990722657,"z":19.21559906005859,"y":-905.1990356445313,"x":-705.6193237304688},"npcSpawn":{"w":306.1168518066406,"z":11.35148334503173,"y":-1083.0777587890626,"x":-805.4105224609375},"purchasePrice":0,"truckStop":{"w":93.00149536132813,"z":19.00942802429199,"y":-916.2830200195313,"x":-725.21435546875},"coords":{"w":72.12774658203125,"z":19.21558570861816,"y":-914.8898315429688,"x":-706.1461791992188},"dropoff":{"w":270.0059814453125,"z":19.21558570861816,"y":-913.3250122070313,"x":-707.691162109375},"npcWalkPoint":{"w":2.60178709030151,"z":19.21418762207031,"y":-917.6209106445313,"x":-711.7567749023438}}', 0, '2026-10-24 04:37:09'),
	('digital_den', '{"purchasable":false,"purchasePrice":0,"id":"digital_den","group":"digital_den","label":"Digital Den","coords":{"z":29.2917,"w":227.0683,"x":393.3369,"y":-832.2006}}', 0, '2026-10-23 19:49:37'),
	('ilegal_shop', '{"group":"ilegal_shop","purchasable":false,"label":"Loja Ilegal","id":"ilegal_shop","purchasePrice":0,"coords":{"w":174.80010986328126,"z":6.06979370117187,"y":-3121.351806640625,"x":503.9720153808594}}', 0, '2026-10-24 04:39:13'),
	('mechanic_products', '{"purchasable":false,"purchasePrice":0,"id":"mechanic_products","group":"mechanic_products","label":"Produtos Mecanica","coords":{"z":29.63684463500976,"w":43.5,"x":46.12448120117187,"y":-1749.7132568359376}}', 0, '2026-10-23 19:49:38'),
	('police_mission_row', '{"purchasable":false,"purchasePrice":0,"id":"police_mission_row","group":"police","label":"Suprimentos policiais","coords":{"z":30.6896,"w":175.9166,"x":451.6492,"y":-979.6264}}', 0, '2026-10-23 19:49:38'),
	('produtos', '{"purchasable":false,"purchasePrice":0,"id":"produtos","group":"produtos","label":"Produtos","coords":{"z":30.16422080993652,"w":357.2,"x":3.21665716171264,"y":-1309.9627685546876}}', 0, '2026-10-23 19:49:38');

-- Copiando estrutura para tabela orcore.ob_inventory_shop_orders
CREATE TABLE IF NOT EXISTS `ob_inventory_shop_orders` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `shop_id` varchar(64) NOT NULL,
  `owner_user_id` bigint(20) unsigned NOT NULL,
  `method` enum('npc','pickup') NOT NULL,
  `status` enum('pending','in_transit','delivered','cancelled','failed') NOT NULL DEFAULT 'pending',
  `cargo_json` longtext NOT NULL,
  `subtotal` bigint(20) unsigned NOT NULL,
  `total_cost` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `completed_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ob_shop_order_active` (`shop_id`,`status`)
) ENGINE=InnoDB AUTO_INCREMENT=28 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_inventory_shop_orders omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_inventory_shop_sales
CREATE TABLE IF NOT EXISTS `ob_inventory_shop_sales` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `shop_id` varchar(64) NOT NULL,
  `buyer_user_id` bigint(20) unsigned DEFAULT NULL,
  `buyer_name` varchar(100) DEFAULT NULL,
  `item_name` varchar(64) NOT NULL,
  `quantity` int(10) unsigned NOT NULL,
  `gross_amount` bigint(20) unsigned NOT NULL,
  `tax_amount` bigint(20) unsigned NOT NULL,
  `net_amount` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ob_shop_sales` (`shop_id`,`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_inventory_shop_sales omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_inventory_shop_stock
CREATE TABLE IF NOT EXISTS `ob_inventory_shop_stock` (
  `shop_id` varchar(64) NOT NULL,
  `slot` smallint(5) unsigned NOT NULL,
  `item_name` varchar(64) NOT NULL,
  `quantity` int(10) unsigned NOT NULL DEFAULT 0,
  `sale_price` int(10) unsigned NOT NULL DEFAULT 0,
  `wholesale_price` int(10) unsigned NOT NULL DEFAULT 0,
  `max_stock` int(10) unsigned NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`shop_id`,`item_name`),
  KEY `idx_ob_shop_stock_slot` (`shop_id`,`slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_inventory_shop_stock omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_leiteiro_progress
CREATE TABLE IF NOT EXISTS `ob_leiteiro_progress` (
  `user_id` bigint(20) unsigned NOT NULL,
  `xp` int(11) NOT NULL DEFAULT 0,
  `level` int(11) NOT NULL DEFAULT 1,
  `boxes_delivered` int(11) NOT NULL DEFAULT 0,
  `total_earned` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_or_leiteiro_progress_character` FOREIGN KEY (`user_id`) REFERENCES `ob_characters` (`user_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_leiteiro_progress omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_license_documents
CREATE TABLE IF NOT EXISTS `ob_license_documents` (
  `user_id` bigint(20) unsigned NOT NULL,
  `identity_issued_at` bigint(20) NOT NULL DEFAULT 0,
  `driver_issued_at` bigint(20) NOT NULL DEFAULT 0,
  `driver_expires_at` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_license_documents omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_licenses
CREATE TABLE IF NOT EXISTS `ob_licenses` (
  `user_id` bigint(20) unsigned NOT NULL,
  `category` varchar(16) NOT NULL,
  `theory` tinyint(4) NOT NULL DEFAULT 0,
  `licensed` tinyint(4) NOT NULL DEFAULT 0,
  `attempts` int(10) unsigned NOT NULL DEFAULT 0,
  `issued_at` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`user_id`,`category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_licenses omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_lumberjack_progress
CREATE TABLE IF NOT EXISTS `ob_lumberjack_progress` (
  `user_id` bigint(20) unsigned NOT NULL,
  `xp` int(11) NOT NULL DEFAULT 0,
  `level` int(11) NOT NULL DEFAULT 1,
  `loads_completed` int(11) NOT NULL DEFAULT 0,
  `total_earned` int(11) NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_or_lumberjack_progress_character` FOREIGN KEY (`user_id`) REFERENCES `ob_characters` (`user_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_lumberjack_progress omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_mdt_clear_audit
CREATE TABLE IF NOT EXISTS `ob_mdt_clear_audit` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `record_id` bigint(20) unsigned NOT NULL,
  `cleaner_user_id` bigint(20) unsigned NOT NULL,
  `cleaner_name` varchar(80) NOT NULL,
  `cleaner_mode` varchar(16) NOT NULL,
  `note` varchar(500) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ob_mdt_audit_record` (`record_id`),
  KEY `idx_ob_mdt_audit_cleaner` (`cleaner_user_id`,`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_mdt_clear_audit omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_mdt_records
CREATE TABLE IF NOT EXISTS `ob_mdt_records` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `suspect_user_id` bigint(20) unsigned NOT NULL,
  `suspect_name` varchar(80) NOT NULL,
  `officer_user_id` bigint(20) unsigned NOT NULL,
  `officer_name` varchar(80) NOT NULL,
  `reason` varchar(1000) NOT NULL,
  `crimes_json` longtext NOT NULL,
  `months` smallint(5) unsigned NOT NULL DEFAULT 0,
  `fine` bigint(20) unsigned NOT NULL DEFAULT 0,
  `fine_status` varchar(16) NOT NULL DEFAULT 'pending',
  `bail_amount` bigint(20) unsigned NOT NULL DEFAULT 0,
  `lawyer_required` tinyint(1) NOT NULL DEFAULT 0,
  `mugshot_url` varchar(500) NOT NULL DEFAULT '',
  `inventory_photo_url` varchar(500) NOT NULL DEFAULT '',
  `seized_items` varchar(1000) NOT NULL DEFAULT '',
  `cleared` tinyint(1) NOT NULL DEFAULT 0,
  `cleared_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 0,
  `cleared_by_name` varchar(80) NOT NULL DEFAULT '',
  `cleared_reason` varchar(500) NOT NULL DEFAULT '',
  `cleared_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ob_mdt_suspect` (`suspect_user_id`,`created_at`),
  KEY `idx_ob_mdt_officer` (`officer_user_id`,`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_mdt_records omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_moneywash_audit
CREATE TABLE IF NOT EXISTS `ob_moneywash_audit` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `transaction_id` bigint(20) unsigned DEFAULT NULL,
  `location_id` int(10) unsigned DEFAULT NULL,
  `user_id` bigint(20) unsigned DEFAULT NULL,
  `actor_user_id` bigint(20) unsigned DEFAULT NULL,
  `event_type` varchar(48) NOT NULL,
  `dirty_balance` bigint(20) unsigned DEFAULT NULL,
  `clean_balance` bigint(20) unsigned DEFAULT NULL,
  `details` longtext DEFAULT NULL,
  `created_at` timestamp(3) NOT NULL DEFAULT current_timestamp(3),
  PRIMARY KEY (`id`),
  KEY `idx_ob_moneywash_audit_transaction` (`transaction_id`,`id`),
  KEY `idx_ob_moneywash_audit_user` (`user_id`,`created_at`),
  KEY `idx_ob_moneywash_audit_event` (`event_type`,`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=35 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_moneywash_audit omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_moneywash_locations
CREATE TABLE IF NOT EXISTS `ob_moneywash_locations` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `label` varchar(80) NOT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  `commission_percent` tinyint(3) unsigned NOT NULL DEFAULT 40,
  `duration_seconds` int(10) unsigned NOT NULL DEFAULT 60,
  `minimum_amount` int(10) unsigned NOT NULL DEFAULT 100,
  `maximum_amount` int(10) unsigned NOT NULL DEFAULT 1000000,
  `ped_model` varchar(64) NOT NULL,
  `ped_scenario` varchar(96) NOT NULL,
  `ped_x` double NOT NULL,
  `ped_y` double NOT NULL,
  `ped_z` double NOT NULL,
  `ped_w` double NOT NULL,
  `machine_model` varchar(64) NOT NULL,
  `machine_open_model` varchar(64) NOT NULL,
  `machine_spin_model` varchar(64) NOT NULL,
  `machine_x` double NOT NULL,
  `machine_y` double NOT NULL,
  `machine_z` double NOT NULL,
  `machine_w` double NOT NULL,
  `action_x` double NOT NULL,
  `action_y` double NOT NULL,
  `action_z` double NOT NULL,
  `action_w` double NOT NULL,
  `created_by` bigint(20) unsigned DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `access_group` varchar(64) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ob_moneywash_enabled` (`enabled`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Copiando dados para a tabela orcore.ob_moneywash_locations: ~0 rows (aproximadamente)
INSERT INTO `ob_moneywash_locations` (`id`, `label`, `enabled`, `commission_percent`, `duration_seconds`, `minimum_amount`, `maximum_amount`, `ped_model`, `ped_scenario`, `ped_x`, `ped_y`, `ped_z`, `ped_w`, `machine_model`, `machine_open_model`, `machine_spin_model`, `machine_x`, `machine_y`, `machine_z`, `machine_w`, `action_x`, `action_y`, `action_z`, `action_w`, `created_by`, `created_at`, `updated_at`, `access_group`) VALUES
	(1, 'Lavagem de dinheiro', 1, 40, 60, 100, 1000000, 's_m_m_highsec_01', 'WORLD_HUMAN_CLIPBOARD', 133.509, -3178.967, 5.858, 173.1, 'bkr_prop_prtmachine_dryer', 'bkr_prop_prtmachine_dryer_op', 'bkr_prop_prtmachine_dryer_spin', 131.594, -3178.941, 4.896, 1.7, 131.656, -3179.951, 5.858, 355.3, 1, '2026-10-26 15:47:24', '2026-10-26 21:19:54', '');

-- Copiando estrutura para tabela orcore.ob_moneywash_machines
CREATE TABLE IF NOT EXISTS `ob_moneywash_machines` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `location_id` int(10) unsigned NOT NULL,
  `label` varchar(80) NOT NULL DEFAULT 'Maquina',
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  `machine_model` varchar(64) NOT NULL,
  `machine_open_model` varchar(64) NOT NULL,
  `machine_spin_model` varchar(64) NOT NULL,
  `machine_x` double NOT NULL,
  `machine_y` double NOT NULL,
  `machine_z` double NOT NULL,
  `machine_w` double NOT NULL,
  `action_x` double NOT NULL,
  `action_y` double NOT NULL,
  `action_z` double NOT NULL,
  `action_w` double NOT NULL,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_ob_moneywash_machine_location` (`location_id`,`enabled`,`sort_order`),
  CONSTRAINT `fk_ob_moneywash_machine_location` FOREIGN KEY (`location_id`) REFERENCES `ob_moneywash_locations` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Copiando dados para a tabela orcore.ob_moneywash_machines: ~0 rows (aproximadamente)
INSERT INTO `ob_moneywash_machines` (`id`, `location_id`, `label`, `enabled`, `machine_model`, `machine_open_model`, `machine_spin_model`, `machine_x`, `machine_y`, `machine_z`, `machine_w`, `action_x`, `action_y`, `action_z`, `action_w`, `sort_order`) VALUES
	(5, 1, 'Maquina 1', 1, 'bkr_prop_prtmachine_dryer', 'bkr_prop_prtmachine_dryer_op', 'bkr_prop_prtmachine_dryer_spin', 131.594, -3178.941, 4.896, 1.7, 131.656, -3179.951, 5.858, 355.3, 1);

-- Copiando estrutura para tabela orcore.ob_moneywash_transactions
CREATE TABLE IF NOT EXISTS `ob_moneywash_transactions` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `location_id` int(10) unsigned NOT NULL,
  `machine_id` int(10) unsigned DEFAULT NULL,
  `user_id` bigint(20) unsigned NOT NULL,
  `dirty_amount` int(10) unsigned NOT NULL,
  `commission_percent` tinyint(3) unsigned NOT NULL,
  `commission_amount` int(10) unsigned NOT NULL,
  `clean_amount` int(10) unsigned NOT NULL,
  `status` enum('processing','ready','paying','completed','refunded','review') NOT NULL DEFAULT 'processing',
  `receipt_code` varchar(32) DEFAULT NULL,
  `dirty_balance_before` bigint(20) unsigned DEFAULT NULL,
  `dirty_balance_after` bigint(20) unsigned DEFAULT NULL,
  `clean_balance_before` bigint(20) unsigned DEFAULT NULL,
  `clean_balance_after` bigint(20) unsigned DEFAULT NULL,
  `payout_started_at` datetime DEFAULT NULL,
  `payout_confirmed_at` datetime DEFAULT NULL,
  `integrity_note` varchar(255) DEFAULT NULL,
  `started_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `finish_at` datetime NOT NULL,
  `completed_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_ob_moneywash_receipt` (`receipt_code`),
  KEY `idx_ob_moneywash_active_location` (`location_id`,`status`),
  KEY `idx_ob_moneywash_active_user` (`user_id`,`status`),
  CONSTRAINT `fk_ob_moneywash_character` FOREIGN KEY (`user_id`) REFERENCES `ob_characters` (`user_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_ob_moneywash_location` FOREIGN KEY (`location_id`) REFERENCES `ob_moneywash_locations` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_moneywash_transactions omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_org_blacklist
CREATE TABLE IF NOT EXISTS `ob_org_blacklist` (
  `user_id` bigint(20) unsigned NOT NULL,
  `previous_org_id` int(10) unsigned DEFAULT NULL,
  `reason` varchar(160) NOT NULL,
  `expires_at` datetime NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`user_id`),
  KEY `idx_ob_org_blacklist_expiry` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_org_blacklist omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_org_chest_logs
CREATE TABLE IF NOT EXISTS `ob_org_chest_logs` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `chest_id` int(10) unsigned NOT NULL,
  `org_id` int(10) unsigned NOT NULL,
  `user_id` bigint(20) unsigned NOT NULL,
  `player_name` varchar(80) NOT NULL,
  `action` enum('deposit','withdraw','discard') NOT NULL,
  `item_name` varchar(64) NOT NULL,
  `amount` int(10) unsigned NOT NULL,
  `metadata` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ob_org_chest_logs_chest` (`chest_id`,`created_at`),
  KEY `idx_ob_org_chest_logs_user` (`user_id`,`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_org_chest_logs omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_org_chests
CREATE TABLE IF NOT EXISTS `ob_org_chests` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `org_id` int(10) unsigned NOT NULL,
  `label` varchar(80) NOT NULL,
  `chest_type` enum('storage','discard') NOT NULL DEFAULT 'storage',
  `slots` int(10) unsigned NOT NULL DEFAULT 30,
  `max_weight` bigint(20) unsigned NOT NULL DEFAULT 100000,
  `coords` text NOT NULL,
  `webhook_url` varchar(1000) DEFAULT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ob_org_chests_org` (`org_id`,`enabled`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Copiando dados para a tabela orcore.ob_org_chests: ~0 rows (aproximadamente)
INSERT INTO `ob_org_chests` (`id`, `org_id`, `label`, `chest_type`, `slots`, `max_weight`, `coords`, `webhook_url`, `enabled`, `created_at`, `updated_at`) VALUES
	(1, 3, 'teste', 'storage', 70, 1000000, '{"z":30.68960571289062,"y":-991.4909057617188,"x":441.91729736328127}', '', 1, '2026-08-29 20:40:20', '2026-08-29 20:40:20');

-- Copiando estrutura para tabela orcore.ob_org_duty_blips
CREATE TABLE IF NOT EXISTS `ob_org_duty_blips` (
  `org_id` int(10) unsigned NOT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  `label` varchar(80) NOT NULL,
  `sprite` int(10) unsigned NOT NULL DEFAULT 1,
  `colour` int(10) unsigned NOT NULL DEFAULT 3,
  `scale` decimal(4,2) NOT NULL DEFAULT 0.75,
  `helicopter_sprite` int(10) unsigned NOT NULL DEFAULT 422,
  `visible_to` text NOT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`org_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Copiando dados para a tabela orcore.ob_org_duty_blips: ~3 rows (aproximadamente)
INSERT INTO `ob_org_duty_blips` (`org_id`, `enabled`, `label`, `sprite`, `colour`, `scale`, `helicopter_sprite`, `visible_to`, `updated_at`) VALUES
	(3, 1, 'Policia', 1, 3, 0.75, 422, '["police"]', '2026-10-29 01:21:56'),
	(4, 1, 'HP', 1, 3, 0.75, 422, '["ambulance"]', '2026-10-29 01:21:55'),
	(8, 1, 'Mecanico', 1, 3, 0.75, 422, '["mechanic"]', '2026-10-29 01:21:56');

-- Copiando estrutura para tabela orcore.ob_org_goal_progress
CREATE TABLE IF NOT EXISTS `ob_org_goal_progress` (
  `goal_id` int(10) unsigned NOT NULL,
  `user_id` bigint(20) unsigned NOT NULL,
  `period_key` date NOT NULL,
  `progress` int(10) unsigned NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`goal_id`,`user_id`,`period_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_org_goal_progress omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_org_goals
CREATE TABLE IF NOT EXISTS `ob_org_goals` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `org_id` int(10) unsigned NOT NULL,
  `title` varchar(100) NOT NULL,
  `target` int(10) unsigned NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ob_org_goals_org` (`org_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Copiando dados para a tabela orcore.ob_org_goals: ~0 rows (aproximadamente)

-- Copiando estrutura para tabela orcore.ob_org_members
CREATE TABLE IF NOT EXISTS `ob_org_members` (
  `org_id` int(10) unsigned NOT NULL,
  `user_id` bigint(20) unsigned NOT NULL,
  `rank_id` int(10) unsigned NOT NULL,
  `on_duty` tinyint(1) NOT NULL DEFAULT 0,
  `joined_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`user_id`),
  KEY `idx_ob_org_members_org` (`org_id`),
  KEY `idx_ob_org_members_rank` (`rank_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_org_members omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_org_ranks
CREATE TABLE IF NOT EXISTS `ob_org_ranks` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `org_id` int(10) unsigned NOT NULL,
  `rank_key` varchar(48) NOT NULL,
  `label` varchar(80) NOT NULL,
  `level` int(10) unsigned NOT NULL,
  `salary` int(10) unsigned NOT NULL DEFAULT 0,
  `member_limit` int(10) unsigned NOT NULL DEFAULT 0,
  `permissions` text NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_ob_org_rank` (`org_id`,`rank_key`),
  KEY `idx_ob_org_rank_level` (`org_id`,`level`)
) ENGINE=InnoDB AUTO_INCREMENT=14 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Copiando dados para a tabela orcore.ob_org_ranks: ~9 rows (aproximadamente)
INSERT INTO `ob_org_ranks` (`id`, `org_id`, `rank_key`, `label`, `level`, `salary`, `member_limit`, `permissions`) VALUES
	(1, 1, 'leader', 'Lider', 1, 0, 1, '{"routes_manage":true,"view":true,"members_add":true,"members_remove":true,"goals_manage":true,"ranks_manage":true,"branding_manage":true,"members_rank":true}'),
	(2, 1, 'member', 'Membro', 100, 0, 0, '{"view":true}'),
	(6, 3, 'delegado', 'Delegado', 1, 1500, 1, '{"view":true,"access":["police"],"members_rank":true,"members_add":true,"members_remove":true,"branding_manage":true,"goals_manage":true}'),
	(7, 3, 'recruta', 'Recruta', 100, 0, 0, '{"view":true,"access":["police"],"members_rank":false,"members_add":false,"members_remove":false,"branding_manage":false,"goals_manage":false}'),
	(8, 4, 'chief', 'Chefia', 1, 0, 1, '{"members_rank":true,"branding_manage":true,"members_remove":true,"goals_manage":true,"view":true,"members_add":true}'),
	(9, 4, 'member', 'Membro', 100, 0, 0, '{"view":true}'),
	(10, 8, 'dono', 'Dono', 1, 2500, 1, '{"access":["mechanic"],"goals_manage":true,"branding_manage":true,"members_add":true,"view":true,"members_rank":true,"members_remove":true}'),
	(11, 8, 'gerente', 'Gerente', 100, 2000, 0, '{"access":["mechanic"],"goals_manage":false,"branding_manage":false,"members_add":true,"view":true,"members_rank":false,"members_remove":true}'),
	(13, 8, 'mecanico', 'Mecanico', 100, 1500, 0, '{"access":["mechanic"],"goals_manage":false,"branding_manage":false,"members_add":false,"view":true,"members_rank":false,"members_remove":false}');

-- Copiando estrutura para tabela orcore.ob_org_route_log
CREATE TABLE IF NOT EXISTS `ob_org_route_log` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `org_id` int(10) unsigned NOT NULL,
  `route_id` int(10) unsigned NOT NULL,
  `user_id` bigint(20) unsigned NOT NULL,
  `completed_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ob_org_route_rank` (`org_id`,`completed_at`),
  KEY `idx_ob_org_route_user` (`user_id`,`completed_at`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_org_route_log omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_org_route_points
CREATE TABLE IF NOT EXISTS `ob_org_route_points` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `route_id` int(10) unsigned NOT NULL,
  `position` int(10) unsigned NOT NULL,
  `x` double NOT NULL,
  `y` double NOT NULL,
  `z` double NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ob_org_points` (`route_id`,`position`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Copiando dados para a tabela orcore.ob_org_route_points: ~0 rows (aproximadamente)

-- Copiando estrutura para tabela orcore.ob_org_route_rewards
CREATE TABLE IF NOT EXISTS `ob_org_route_rewards` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `route_id` int(10) unsigned NOT NULL,
  `item_name` varchar(64) NOT NULL,
  `min_amount` int(10) unsigned NOT NULL,
  `max_amount` int(10) unsigned NOT NULL,
  `chance` decimal(5,2) NOT NULL DEFAULT 100.00,
  PRIMARY KEY (`id`),
  KEY `idx_ob_org_rewards_route` (`route_id`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Copiando dados para a tabela orcore.ob_org_route_rewards: ~0 rows (aproximadamente)

-- Copiando estrutura para tabela orcore.ob_org_routes
CREATE TABLE IF NOT EXISTS `ob_org_routes` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `org_id` int(10) unsigned NOT NULL,
  `name` varchar(80) NOT NULL,
  `npc_model` varchar(80) NOT NULL DEFAULT 'g_m_y_mexgoon_01',
  `npc_coords` text DEFAULT NULL,
  `max_rewards` int(10) unsigned NOT NULL DEFAULT 1,
  `collect_duration` int(10) unsigned NOT NULL DEFAULT 3000,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `idx_ob_org_routes_org` (`org_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Copiando dados para a tabela orcore.ob_org_routes: ~0 rows (aproximadamente)

-- Copiando estrutura para tabela orcore.ob_orgs
CREATE TABLE IF NOT EXISTS `ob_orgs` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `org_key` varchar(48) NOT NULL,
  `label` varchar(80) NOT NULL,
  `logo_url` varchar(512) DEFAULT NULL,
  `org_type` enum('legal','illegal') NOT NULL,
  `max_members` int(10) unsigned NOT NULL DEFAULT 250,
  `auto_duty` tinyint(1) NOT NULL DEFAULT 0,
  `duty_coords` text DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_ob_org_key` (`org_key`)
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Copiando dados para a tabela orcore.ob_orgs: ~4 rows (aproximadamente)
INSERT INTO `ob_orgs` (`id`, `org_key`, `label`, `logo_url`, `org_type`, `max_members`, `auto_duty`, `duty_coords`, `active`, `created_at`, `updated_at`) VALUES
	(1, 'fac1', 'fac do morro', NULL, 'illegal', 50, 1, NULL, 1, '2026-08-28 00:59:55', '2026-08-28 00:59:55'),
	(3, 'police', 'Policia', '', 'legal', 50, 0, '{"x":440.3998107910156,"z":30.68960380554199,"y":-975.6742553710938}', 1, '2026-08-28 03:32:21', '2026-08-28 03:32:43'),
	(4, 'ambulance', 'HP', '', 'legal', 100, 0, '{"z":43.29185104370117,"x":305.213134765625,"y":-597.6487426757813}', 1, '2026-09-09 04:09:57', '2026-09-09 04:12:35'),
	(8, 'mechanic', 'Mecanico', NULL, 'legal', 20, 0, NULL, 1, '2026-10-23 15:31:15', '2026-10-23 15:31:15');

-- Copiando estrutura para tabela orcore.ob_patrol_route_points
CREATE TABLE IF NOT EXISTS `ob_patrol_route_points` (
  `route_id` bigint(20) unsigned NOT NULL,
  `position` smallint(5) unsigned NOT NULL,
  `x` double NOT NULL,
  `y` double NOT NULL,
  `z` double NOT NULL,
  PRIMARY KEY (`route_id`,`position`),
  CONSTRAINT `fk_ob_patrol_route_points` FOREIGN KEY (`route_id`) REFERENCES `ob_patrol_routes` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Copiando dados para a tabela orcore.ob_patrol_route_points: ~45 rows (aproximadamente)
INSERT INTO `ob_patrol_route_points` (`route_id`, `position`, `x`, `y`, `z`) VALUES
	(1, 1, 438.95001220703125, -981.5800170898438, 30.690000534057617),
	(1, 2, 307.1000061035156, -760.8400268554688, 29.309999465942383),
	(1, 3, 87.95999908447266, -1002.25, 29.399999618530273),
	(1, 4, -292.3500061035156, -987.5399780273438, 31.079999923706055),
	(1, 5, -552.1400146484375, -851.1900024414062, 27.760000228881836),
	(1, 6, -322.05999755859375, -648.9099731445312, 32.349998474121094),
	(1, 7, 76.47000122070312, -676.8200073242188, 31.719999313354492),
	(1, 8, 304.69000244140625, -851.4400024414062, 29.25),
	(2, 1, 367.5199890136719, -1601.760009765625, 29.290000915527344),
	(2, 2, 110.18000030517578, -1772.800048828125, 29.209999084472656),
	(2, 3, -148.02000427246094, -2014.469970703125, 22.8799991607666),
	(2, 4, -301.7900085449219, -2696.39990234375, 6),
	(2, 5, 145.9600067138672, -3030.6298828125, 7.039999961853027),
	(2, 6, 716.22998046875, -2992.22998046875, 6.019999980926514),
	(2, 7, 929.8400268554688, -2523.2900390625, 28.309999465942383),
	(2, 8, 653.8900146484375, -1817.550048828125, 25.6200008392334),
	(3, 1, -1091.699951171875, -807.1599731445312, 19.280000686645508),
	(3, 2, -1294.449951171875, -568.7899780273438, 30.56999969482422),
	(3, 3, -1428.1300048828125, -286.0899963378906, 46.20000076293945),
	(3, 4, -1575.8800048828125, -526.27001953125, 35.060001373291016),
	(3, 5, -1449.8399658203125, -872.77001953125, 10.170000076293945),
	(3, 6, -1220.719970703125, -1127.3399658203125, 7.639999866485596),
	(3, 7, -929.3099975585938, -1198.43994140625, 4.949999809265137),
	(3, 8, -758.5, -1046.06005859375, 12.390000343322754),
	(4, 1, 1854.9200439453125, 3675.580078125, 33.720001220703125),
	(4, 2, 1698.219970703125, 3595.18994140625, 35.470001220703125),
	(4, 3, 1448.9300537109375, 3602.260009765625, 34.86000061035156),
	(4, 4, 1535.8900146484375, 3778.320068359375, 34.5099983215332),
	(4, 5, 1708.31005859375, 3847.43994140625, 34.93000030517578),
	(4, 6, 1953.6300048828125, 3743.169921875, 32.290000915527344),
	(5, 1, -447.3500061035156, 6012.64990234375, 31.719999313354492),
	(5, 2, -277.2099914550781, 6174.81982421875, 31.5),
	(5, 3, -113.8499984741211, 6324.259765625, 31.579999923706055),
	(5, 4, 137.25999450683594, 6558.75, 31.81999969482422),
	(5, 5, 49.720001220703125, 6643.16015625, 31.690000534057617),
	(5, 6, -223.42999267578125, 6434.72021484375, 31.200000762939453),
	(5, 7, -363.489990234375, 6217.31005859375, 31.489999771118164),
	(6, 1, 2570.10009765625, 3077.489990234375, 43.06999969482422),
	(6, 2, 2702.93994140625, 3456.6298828125, 55.77000045776367),
	(6, 3, 2482.5400390625, 4097.7099609375, 38.119998931884766),
	(6, 4, 1966.93994140625, 4642.27978515625, 40.790000915527344),
	(6, 5, 1694.6500244140625, 4876.2099609375, 42.040000915527344),
	(6, 6, 1304.0999755859375, 5662.41015625, 54.31999969482422),
	(6, 7, 558.6300048828125, 6553.240234375, 27.989999771118164),
	(6, 8, 151.00999450683594, 6586.6201171875, 31.84000015258789);

-- Copiando estrutura para tabela orcore.ob_patrol_routes
CREATE TABLE IF NOT EXISTS `ob_patrol_routes` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `slug` varchar(64) NOT NULL,
  `region` varchar(8) NOT NULL,
  `label` varchar(64) NOT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  `created_by` bigint(20) unsigned DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_ob_patrol_route_slug` (`slug`),
  KEY `idx_ob_patrol_region` (`region`,`enabled`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Copiando dados para a tabela orcore.ob_patrol_routes: ~6 rows (aproximadamente)
INSERT INTO `ob_patrol_routes` (`id`, `slug`, `region`, `label`, `enabled`, `created_by`, `created_at`, `updated_at`) VALUES
	(1, 'south_central', 'south', 'Centro e Mission Row', 1, NULL, '2026-10-19 22:50:10', '2026-10-19 22:50:10'),
	(2, 'south_davis_port', 'south', 'Davis e Porto', 1, NULL, '2026-10-19 22:50:10', '2026-10-19 22:50:10'),
	(3, 'south_vespucci', 'south', 'Vespucci e Del Perro', 1, NULL, '2026-10-19 22:50:11', '2026-10-19 22:50:11'),
	(4, 'north_sandy', 'north', 'Sandy Shores', 1, NULL, '2026-10-19 22:50:11', '2026-10-19 22:50:11'),
	(5, 'north_paleto', 'north', 'Paleto Bay', 1, NULL, '2026-10-19 22:50:11', '2026-10-19 22:50:11'),
	(6, 'north_highway', 'north', 'Rodovia Norte', 1, NULL, '2026-10-19 22:50:11', '2026-10-19 22:50:11');

-- Copiando estrutura para tabela orcore.ob_phone_apps
CREATE TABLE IF NOT EXISTS `ob_phone_apps` (
  `user_id` int(11) NOT NULL,
  `app_id` varchar(48) NOT NULL,
  `installed` tinyint(1) NOT NULL DEFAULT 1,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`,`app_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_apps omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_calls
CREATE TABLE IF NOT EXISTS `ob_phone_calls` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `caller_id` int(11) NOT NULL,
  `callee_id` int(11) NOT NULL,
  `caller_number` varchar(16) NOT NULL,
  `callee_number` varchar(16) NOT NULL,
  `call_type` varchar(8) NOT NULL DEFAULT 'voice',
  `status` varchar(24) NOT NULL,
  `duration` int(10) unsigned NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_call_caller` (`caller_id`,`id`),
  KEY `idx_call_callee` (`callee_id`,`id`)
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_calls omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_contacts
CREATE TABLE IF NOT EXISTS `ob_phone_contacts` (
  `user_id` int(11) NOT NULL,
  `contact_number` varchar(16) NOT NULL,
  `contact_name` varchar(40) NOT NULL,
  PRIMARY KEY (`user_id`,`contact_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_contacts omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_dark_groups
CREATE TABLE IF NOT EXISTS `ob_phone_dark_groups` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `owner_id` int(11) NOT NULL,
  `name` varchar(40) NOT NULL,
  `invite_code` varchar(20) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `invite_code` (`invite_code`),
  KEY `idx_dark_owner` (`owner_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_dark_groups omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_dark_members
CREATE TABLE IF NOT EXISTS `ob_phone_dark_members` (
  `group_id` bigint(20) unsigned NOT NULL,
  `user_id` int(11) NOT NULL,
  `joined_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`group_id`,`user_id`),
  KEY `idx_dark_member` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_dark_members omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_dark_messages
CREATE TABLE IF NOT EXISTS `ob_phone_dark_messages` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `group_id` bigint(20) unsigned NOT NULL,
  `user_id` int(11) NOT NULL,
  `body` varchar(500) NOT NULL DEFAULT '',
  `media_url` varchar(700) DEFAULT NULL,
  `media_type` varchar(12) NOT NULL DEFAULT 'text',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_dark_messages` (`group_id`,`id`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_dark_messages omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_device_profiles
CREATE TABLE IF NOT EXISTS `ob_phone_device_profiles` (
  `user_id` int(11) NOT NULL,
  `avatar_url` varchar(700) DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_device_profiles omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_devices
CREATE TABLE IF NOT EXISTS `ob_phone_devices` (
  `device_id` varchar(48) NOT NULL,
  `owner_user_id` int(11) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `pin_hash` char(64) DEFAULT NULL,
  `face_enabled` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`device_id`),
  KEY `idx_phone_device_owner` (`owner_user_id`,`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_devices omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_follows
CREATE TABLE IF NOT EXISTS `ob_phone_follows` (
  `follower_id` int(11) NOT NULL,
  `followed_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`follower_id`,`followed_id`),
  KEY `idx_phone_followed` (`followed_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_follows omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_media
CREATE TABLE IF NOT EXISTS `ob_phone_media` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `remote_id` varchar(160) NOT NULL,
  `media_type` enum('photo','video','audio') NOT NULL,
  `media_url` varchar(700) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_phone_media_user` (`user_id`,`id`)
) ENGINE=InnoDB AUTO_INCREMENT=28 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_media omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_media_variants
CREATE TABLE IF NOT EXISTS `ob_phone_media_variants` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `source_media_id` bigint(20) unsigned NOT NULL,
  `remote_id` varchar(160) NOT NULL,
  `media_url` varchar(700) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_phone_media_variant_user` (`user_id`,`id`),
  KEY `idx_phone_media_variant_source` (`source_media_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_media_variants omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_message_group_members
CREATE TABLE IF NOT EXISTS `ob_phone_message_group_members` (
  `group_id` bigint(20) unsigned NOT NULL,
  `user_id` int(11) NOT NULL,
  `role` varchar(12) NOT NULL DEFAULT 'member',
  `joined_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`group_id`,`user_id`),
  KEY `idx_message_member` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_message_group_members omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_message_group_messages
CREATE TABLE IF NOT EXISTS `ob_phone_message_group_messages` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `group_id` bigint(20) unsigned NOT NULL,
  `user_id` int(11) NOT NULL,
  `body` varchar(500) NOT NULL DEFAULT '',
  `message_type` varchar(12) NOT NULL DEFAULT 'text',
  `media_url` varchar(700) NOT NULL DEFAULT '',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_message_group_messages` (`group_id`,`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_message_group_messages omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_message_groups
CREATE TABLE IF NOT EXISTS `ob_phone_message_groups` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `owner_id` int(11) NOT NULL,
  `name` varchar(40) NOT NULL,
  `invite_permission` varchar(12) NOT NULL DEFAULT 'moderators',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_message_group_owner` (`owner_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_message_groups omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_messages
CREATE TABLE IF NOT EXISTS `ob_phone_messages` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `sender_id` int(11) NOT NULL,
  `recipient_phone` varchar(20) NOT NULL,
  `body` varchar(500) NOT NULL,
  `message_type` varchar(12) NOT NULL DEFAULT 'text',
  `media_url` varchar(700) DEFAULT NULL,
  `contact_name` varchar(40) DEFAULT NULL,
  `contact_number` varchar(16) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_phone_recipient` (`recipient_phone`,`id`)
) ENGINE=InnoDB AUTO_INCREMENT=16 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_messages omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_numbers
CREATE TABLE IF NOT EXISTS `ob_phone_numbers` (
  `user_id` int(11) NOT NULL,
  `phone_number` varchar(16) NOT NULL,
  `battery` tinyint(3) unsigned NOT NULL DEFAULT 100,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`),
  UNIQUE KEY `phone_number` (`phone_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_numbers omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_post_comments
CREATE TABLE IF NOT EXISTS `ob_phone_post_comments` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `post_id` bigint(20) unsigned NOT NULL,
  `user_id` int(11) NOT NULL,
  `body` varchar(180) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_phone_comment_post` (`post_id`,`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_post_comments omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_post_likes
CREATE TABLE IF NOT EXISTS `ob_phone_post_likes` (
  `post_id` bigint(20) unsigned NOT NULL,
  `user_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`post_id`,`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_post_likes omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_post_media
CREATE TABLE IF NOT EXISTS `ob_phone_post_media` (
  `post_id` bigint(20) unsigned NOT NULL,
  `media_url` varchar(700) NOT NULL,
  `media_type` enum('photo','video') NOT NULL,
  PRIMARY KEY (`post_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_post_media omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_posts
CREATE TABLE IF NOT EXISTS `ob_phone_posts` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `body` varchar(350) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_posts omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_profile_media
CREATE TABLE IF NOT EXISTS `ob_phone_profile_media` (
  `user_id` int(11) NOT NULL,
  `avatar_url` varchar(700) DEFAULT NULL,
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_profile_media omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_profiles
CREATE TABLE IF NOT EXISTS `ob_phone_profiles` (
  `user_id` int(11) NOT NULL,
  `username` varchar(24) NOT NULL,
  `display_name` varchar(32) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`user_id`),
  UNIQUE KEY `username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_profiles omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_settings
CREATE TABLE IF NOT EXISTS `ob_phone_settings` (
  `user_id` int(11) NOT NULL,
  `airplane_mode` tinyint(1) NOT NULL DEFAULT 0,
  `notifications` tinyint(1) NOT NULL DEFAULT 1,
  `darkchat_notifications` tinyint(1) NOT NULL DEFAULT 1,
  `ringtone` varchar(20) NOT NULL DEFAULT 'classic',
  `share_name` varchar(40) DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_settings omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_stories
CREATE TABLE IF NOT EXISTS `ob_phone_stories` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `media_url` varchar(700) NOT NULL,
  `media_type` enum('photo','video') NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `expires_at` timestamp NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_phone_story_expiry` (`expires_at`),
  KEY `idx_phone_story_user` (`user_id`,`id`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_stories omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_phone_story_views
CREATE TABLE IF NOT EXISTS `ob_phone_story_views` (
  `story_id` bigint(20) unsigned NOT NULL,
  `user_id` int(11) NOT NULL,
  `viewed_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`story_id`,`user_id`),
  KEY `idx_story_view_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_phone_story_views omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_player_vehicles
CREATE TABLE IF NOT EXISTS `ob_player_vehicles` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) unsigned NOT NULL,
  `shop_id` int(10) unsigned DEFAULT NULL,
  `plate` varchar(12) NOT NULL,
  `model` varchar(64) NOT NULL,
  `label` varchar(80) NOT NULL,
  `properties` longtext DEFAULT NULL,
  `state` varchar(32) NOT NULL DEFAULT 'stored',
  `purchased_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_ob_player_vehicles_plate` (`plate`),
  KEY `idx_ob_player_vehicles_user` (`user_id`),
  KEY `fk_ob_player_vehicles_shop` (`shop_id`),
  CONSTRAINT `fk_ob_player_vehicles_shop` FOREIGN KEY (`shop_id`) REFERENCES `ob_carshops` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_ob_player_vehicles_user` FOREIGN KEY (`user_id`) REFERENCES `ob_characters` (`user_id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_player_vehicles omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_players
CREATE TABLE IF NOT EXISTS `ob_players` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `license` varchar(80) NOT NULL,
  `fivem_identifier` varchar(80) DEFAULT NULL,
  `display_name` varchar(100) DEFAULT NULL,
  `first_seen_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `last_seen_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_ob_players_id` (`id`),
  UNIQUE KEY `uq_ob_players_license` (`license`),
  KEY `idx_or_players_fivem_identifier` (`fivem_identifier`)
) ENGINE=InnoDB AUTO_INCREMENT=363 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_players omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_police_restraints
CREATE TABLE IF NOT EXISTS `ob_police_restraints` (
  `user_id` bigint(20) unsigned NOT NULL,
  `restrained` tinyint(1) NOT NULL DEFAULT 1,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_police_restraints omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_prison_activity
CREATE TABLE IF NOT EXISTS `ob_prison_activity` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `sentence_id` bigint(20) unsigned NOT NULL,
  `user_id` bigint(20) unsigned NOT NULL,
  `actor_user_id` bigint(20) unsigned NOT NULL DEFAULT 0,
  `action_name` varchar(32) NOT NULL,
  `detail` varchar(500) NOT NULL DEFAULT '',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ob_prison_activity_user` (`user_id`,`created_at`),
  KEY `idx_ob_prison_activity_sentence` (`sentence_id`)
) ENGINE=InnoDB AUTO_INCREMENT=22 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_prison_activity omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_prison_sentences
CREATE TABLE IF NOT EXISTS `ob_prison_sentences` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `mdt_record_id` bigint(20) unsigned NOT NULL DEFAULT 0,
  `user_id` bigint(20) unsigned NOT NULL,
  `total_seconds` int(10) unsigned NOT NULL,
  `remaining_seconds` int(10) unsigned NOT NULL,
  `reason` varchar(500) NOT NULL,
  `sentenced_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 0,
  `sentenced_by_name` varchar(80) NOT NULL DEFAULT 'Sistema',
  `status` varchar(20) NOT NULL DEFAULT 'active',
  `active_service` varchar(48) DEFAULT NULL,
  `current_point` smallint(5) unsigned DEFAULT NULL,
  `completed_services` int(10) unsigned NOT NULL DEFAULT 0,
  `escape_stage` smallint(5) unsigned NOT NULL DEFAULT 0,
  `release_reason` varchar(255) DEFAULT NULL,
  `sentenced_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `completed_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ob_prison_user_status` (`user_id`,`status`),
  KEY `idx_ob_prison_mdt_record` (`mdt_record_id`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_prison_sentences omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_starterkit_claims
CREATE TABLE IF NOT EXISTS `ob_starterkit_claims` (
  `user_id` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `delivered_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_ob_starterkit_character` FOREIGN KEY (`user_id`) REFERENCES `ob_characters` (`user_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_starterkit_claims omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_store_locations
CREATE TABLE IF NOT EXISTS `ob_store_locations` (
  `id` varchar(64) NOT NULL,
  `data` longtext NOT NULL,
  `deleted` tinyint(4) NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Copiando dados para a tabela orcore.ob_store_locations: ~34 rows (aproximadamente)
INSERT INTO `ob_store_locations` (`id`, `data`, `deleted`, `updated_at`) VALUES
	('__seed_v1', '{}', 1, '2026-09-06 04:14:02'),
	('barber_city', '{"defaultSection":"barbershop","title":"Barbearia","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":71,"color":3,"scale":0.72},"radius":1.65,"categories":["hair","eyebrows","eyes","makeup","blush","lipstick","facialHair"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["barbershop"],"coords":{"z":29.29159927368164,"w":0,"x":137.45570373535157,"y":-1708.30419921875},"heading":140.0,"label":"Barbearia","kind":"barber","id":"barber_city"}', 0, '2026-09-06 04:14:00'),
	('barber_grapeseed', '{"defaultSection":"barbershop","title":"Barbearia","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":71,"color":3,"scale":0.72},"radius":1.65,"categories":["hair","eyebrows","eyes","makeup","blush","lipstick","facialHair"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["barbershop"],"coords":{"z":66.20800018310547,"w":0,"x":1212.180908203125,"y":-473.52630615234377},"heading":338.0,"label":"Barbearia","kind":"barber","id":"barber_grapeseed"}', 0, '2026-09-06 04:14:02'),
	('barber_paleto', '{"defaultSection":"barbershop","title":"Barbearia","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":71,"color":3,"scale":0.72},"radius":1.65,"categories":["hair","eyebrows","eyes","makeup","blush","lipstick","facialHair"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["barbershop"],"coords":{"z":31.69560050964355,"w":0,"x":-278.7738952636719,"y":6227.56982421875},"heading":310.0,"label":"Barbearia","kind":"barber","id":"barber_paleto"}', 0, '2026-09-06 04:14:01'),
	('barber_sandy', '{"defaultSection":"barbershop","title":"Barbearia","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":71,"color":3,"scale":0.72},"radius":1.65,"categories":["hair","eyebrows","eyes","makeup","blush","lipstick","facialHair"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["barbershop"],"coords":{"z":32.84439849853515,"w":0,"x":1932.3798828125,"y":3730.571533203125},"heading":210.0,"label":"Barbearia","kind":"barber","id":"barber_sandy"}', 0, '2026-09-06 04:14:01'),
	('barber_vespucci', '{"defaultSection":"barbershop","title":"Barbearia","lookAtOffset":{"z":0.5,"w":0,"x":0,"y":0},"blip":{"sprite":71,"color":3,"scale":0.72},"radius":1.65,"categories":["hair","eyebrows","eyes","makeup","blush","lipstick","facialHair"],"camOffset":{"z":0.55000001192092,"w":0,"x":0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["barbershop"],"coords":{"z":6.99009990692138,"w":90,"x":-1282.777587890625,"y":-1118.045166015625},"heading":90,"label":"Barbearia","kind":"barber","id":"barber_vespucci"}', 0, '2026-09-06 04:25:56'),
	('barber_vespucci_beach', '{"requireDuty":false,"markerEnabled":true,"title":"Tatuagens","kind":"tattoo","defaultSection":"tattoos","camOffset":{"w":0,"x":0,"y":2.59999990463256,"z":0.55000001192092},"categories":["tat_head","tat_torso","tat_left_arm","tat_right_arm","tat_left_leg","tat_right_leg"],"blip":{"sprite":75,"color":3,"scale":0.72},"coords":{"w":21.5,"x":-1154.019775390625,"y":-1425.3056640625,"z":4.95310020446777},"allowedSections":["tattoos"],"heading":21.5,"label":"Tatuagens","lookAtOffset":{"w":0,"x":0,"y":0,"z":0.5},"radius":1.65,"id":"barber_vespucci_beach"}', 0, '2026-09-06 04:31:05'),
	('barber_vinewood', '{"defaultSection":"barbershop","title":"Barbearia","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":71,"color":3,"scale":0.72},"radius":1.65,"categories":["hair","eyebrows","eyes","makeup","blush","lipstick","facialHair"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["barbershop"],"coords":{"z":57.07649993896484,"w":0,"x":-33.71810150146484,"y":-152.12319946289063},"heading":245.5,"label":"Barbearia","kind":"barber","id":"barber_vinewood"}', 0, '2026-09-06 04:14:02'),
	('clothes_chumash', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":20.86319923400879,"w":0,"x":-3175.44287109375,"y":1041.8797607421876},"heading":335.8,"label":"Loja de roupas","kind":"clothing","id":"clothes_chumash"}', 0, '2026-09-06 04:14:02'),
	('clothes_city', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":29.49110031127929,"w":0,"x":425.5578918457031,"y":-800.422607421875},"heading":85.0,"label":"Loja de roupas","kind":"clothing","id":"clothes_city"}', 0, '2026-09-06 04:14:00'),
	('clothes_city_second', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":29.49110031127929,"w":0,"x":430.1119079589844,"y":-800.3767700195313},"heading":172.8,"label":"Loja de roupas","kind":"clothing","id":"clothes_city_second"}', 0, '2026-09-06 04:14:01'),
	('clothes_grapeseed', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":38.22259902954101,"w":0,"x":1190.659423828125,"y":2710.19921875},"heading":180.0,"label":"Loja de roupas","kind":"clothing","id":"clothes_grapeseed"}', 0, '2026-09-06 04:14:00'),
	('clothes_grapeseed_second', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":38.22259902954101,"w":0,"x":1190.7889404296876,"y":2714.72509765625},"heading":262.1,"label":"Loja de roupas","kind":"clothing","id":"clothes_grapeseed_second"}', 0, '2026-09-06 04:14:02'),
	('clothes_harmony', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":29.37619972229004,"w":0,"x":75.39630126953125,"y":-1398.63671875},"heading":270.0,"label":"Loja de roupas","kind":"clothing","id":"clothes_harmony"}', 0, '2026-09-06 04:14:00'),
	('clothes_harmony_second', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":29.37619972229004,"w":0,"x":70.81189727783203,"y":-1398.8197021484376},"heading":357.6,"label":"Loja de roupas","kind":"clothing","id":"clothes_harmony_second"}', 0, '2026-09-06 04:14:01'),
	('clothes_hawick', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":17.32539939880371,"w":0,"x":-1187.8978271484376,"y":-768.6928100585938},"heading":115.1,"label":"Loja de roupas","kind":"clothing","id":"clothes_hawick"}', 0, '2026-09-06 04:14:01'),
	('clothes_hawick_second', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":39.73329925537109,"w":0,"x":-162.6909942626953,"y":-303.25421142578127},"heading":242.0,"label":"Loja de roupas","kind":"clothing","id":"clothes_hawick_second"}', 0, '2026-09-06 04:14:01'),
	('clothes_paleto', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":31.87789916992187,"w":0,"x":9.1575002670288,"y":6516.47119140625},"heading":45.0,"label":"Loja de roupas","kind":"clothing","id":"clothes_paleto"}', 0, '2026-09-06 04:14:00'),
	('clothes_paleto_second', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":31.87789916992187,"w":0,"x":12.22920036315918,"y":6513.19921875},"heading":130.1,"label":"Loja de roupas","kind":"clothing","id":"clothes_paleto_second"}', 0, '2026-09-06 04:14:02'),
	('clothes_rockford', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":49.80849838256836,"w":0,"x":-1450.9771728515626,"y":-236.59140014648438},"heading":46.8,"label":"Loja de roupas","kind":"clothing","id":"clothes_rockford"}', 0, '2026-09-06 04:14:02'),
	('clothes_route68', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":42.08810043334961,"w":0,"x":617.5579833984375,"y":2766.7001953125},"heading":182.7,"label":"Loja de roupas","kind":"clothing","id":"clothes_route68"}', 0, '2026-09-06 04:14:02'),
	('clothes_sandy', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":42.0630989074707,"w":0,"x":1693.1612548828126,"y":4828.6953125},"heading":98.0,"label":"Loja de roupas","kind":"clothing","id":"clothes_sandy"}', 0, '2026-09-06 04:14:00'),
	('clothes_sandy_second', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":42.0630989074707,"w":0,"x":1697.638916015625,"y":4829.19921875},"heading":183.9,"label":"Loja de roupas","kind":"clothing","id":"clothes_sandy_second"}', 0, '2026-09-06 04:14:01'),
	('clothes_senora', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":19.10779953002929,"w":0,"x":-1105.8291015625,"y":2706.692138671875},"heading":301.7,"label":"Loja de roupas","kind":"clothing","id":"clothes_senora"}', 0, '2026-09-06 04:14:02'),
	('clothes_senora_second', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":19.10779953002929,"w":0,"x":-1108.7913818359376,"y":2710.141357421875},"heading":301.7,"label":"Loja de roupas","kind":"clothing","id":"clothes_senora_second"}', 0, '2026-09-06 04:14:02'),
	('clothes_vespucci', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":37.41510009765625,"w":0,"x":-710.5551147460938,"y":-153.30389404296876},"heading":120.0,"label":"Loja de roupas","kind":"clothing","id":"clothes_vespucci"}', 0, '2026-09-06 04:14:00'),
	('clothes_vespucci_second', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":11.32810020446777,"w":0,"x":-827.4508056640625,"y":-1076.486328125},"heading":291.3,"label":"Loja de roupas","kind":"clothing","id":"clothes_vespucci_second"}', 0, '2026-09-06 04:14:01'),
	('clothes_vespucci_third', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":11.32810020446777,"w":0,"x":-829.7877807617188,"y":-1072.5916748046876},"heading":291.3,"label":"Loja de roupas","kind":"clothing","id":"clothes_vespucci_third"}', 0, '2026-09-06 04:14:01'),
	('clothes_vinewood', '{"defaultSection":"skinshop","title":"Loja de roupas","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":73,"color":3,"scale":0.72},"radius":1.65,"categories":["tops","torsos","legs","shoes","undershirts","bags","bodyArmors","hats","glasses","watches"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["skinshop"],"coords":{"z":54.55780029296875,"w":0,"x":121.11039733886719,"y":-225.8343963623047},"heading":334.2,"label":"Loja de roupas","kind":"clothing","id":"clothes_vinewood"}', 0, '2026-09-06 04:14:02'),
	('tattoo_chumash', '{"defaultSection":"tattoos","title":"Tatuagens","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":75,"color":3,"scale":0.72},"radius":1.65,"categories":["tat_head","tat_torso","tat_left_arm","tat_right_arm","tat_left_leg","tat_right_leg"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["tattoos"],"coords":{"z":20.8292007446289,"w":0,"x":-3170.242431640625,"y":1075.3109130859376},"heading":244.0,"label":"Tatuagens","kind":"tattoo","id":"tattoo_chumash"}', 0, '2026-09-06 04:14:01'),
	('tattoo_city', '{"defaultSection":"tattoos","title":"Tatuagens","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":75,"color":3,"scale":0.72},"radius":1.65,"categories":["tat_head","tat_torso","tat_left_arm","tat_right_arm","tat_left_leg","tat_right_leg"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["tattoos"],"coords":{"z":52.27529907226562,"w":0,"x":1323.1583251953126,"y":-1652.391357421875},"heading":32.0,"label":"Tatuagens","kind":"tattoo","id":"tattoo_city"}', 0, '2026-09-06 04:14:01'),
	('tattoo_paleto', '{"defaultSection":"tattoos","title":"Tatuagens","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":75,"color":3,"scale":0.72},"radius":1.65,"categories":["tat_head","tat_torso","tat_left_arm","tat_right_arm","tat_left_leg","tat_right_leg"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["tattoos"],"coords":{"z":31.48710060119629,"w":0,"x":-293.85540771484377,"y":6200.509765625},"heading":189.0,"label":"Tatuagens","kind":"tattoo","id":"tattoo_paleto"}', 0, '2026-09-06 04:14:01'),
	('tattoo_sandy', '{"defaultSection":"tattoos","title":"Tatuagens","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":75,"color":3,"scale":0.72},"radius":1.65,"categories":["tat_head","tat_torso","tat_left_arm","tat_right_arm","tat_left_leg","tat_right_leg"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["tattoos"],"coords":{"z":33.03179931640625,"w":0,"x":1863.9537353515626,"y":3747.341552734375},"heading":4.0,"label":"Tatuagens","kind":"tattoo","id":"tattoo_sandy"}', 0, '2026-09-06 04:14:01'),
	('tattoo_west', '{"defaultSection":"tattoos","title":"Tatuagens","lookAtOffset":{"z":0.5,"w":0,"x":0.0,"y":0.0},"blip":{"sprite":75,"color":3,"scale":0.72},"radius":1.65,"categories":["tat_head","tat_torso","tat_left_arm","tat_right_arm","tat_left_leg","tat_right_leg"],"camOffset":{"z":0.55000001192092,"w":0,"x":0.0,"y":2.59999990463256},"markerEnabled":true,"requireDuty":false,"allowedSections":["tattoos"],"coords":{"z":103.58650207519531,"w":0,"x":321.93109130859377,"y":180.71490478515626},"heading":157.0,"label":"Tatuagens","kind":"tattoo","id":"tattoo_west"}', 0, '2026-09-06 04:14:01');

-- Copiando estrutura para tabela orcore.ob_taxi_progress
CREATE TABLE IF NOT EXISTS `ob_taxi_progress` (
  `user_id` bigint(20) unsigned NOT NULL,
  `xp` int(11) NOT NULL DEFAULT 0,
  `level` int(11) NOT NULL DEFAULT 1,
  `rides` int(11) NOT NULL DEFAULT 0,
  `total_earned` int(11) NOT NULL DEFAULT 0,
  `best_fare` int(11) NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_or_taxi_progress_character` FOREIGN KEY (`user_id`) REFERENCES `ob_characters` (`user_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_taxi_progress omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_trucker_progress
CREATE TABLE IF NOT EXISTS `ob_trucker_progress` (
  `user_id` bigint(20) unsigned NOT NULL,
  `xp` int(11) NOT NULL DEFAULT 0,
  `level` int(11) NOT NULL DEFAULT 1,
  `deliveries_completed` int(11) NOT NULL DEFAULT 0,
  `total_earned` bigint(20) NOT NULL DEFAULT 0,
  `distance_skill` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `cargo_skill` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `care_skill` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `efficiency_skill` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_ob_trucker_progress_character` FOREIGN KEY (`user_id`) REFERENCES `ob_characters` (`user_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dados de ob_trucker_progress omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_vehicle_ignitions
CREATE TABLE IF NOT EXISTS `ob_vehicle_ignitions` (
  `vehicle_identity` varchar(96) NOT NULL,
  `user_id` bigint(20) unsigned NOT NULL,
  `key_id` bigint(20) unsigned NOT NULL,
  `disposition` varchar(12) NOT NULL DEFAULT 'active',
  PRIMARY KEY (`vehicle_identity`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_vehicle_ignitions omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_vehicle_keys
CREATE TABLE IF NOT EXISTS `ob_vehicle_keys` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `vehicle_identity` varchar(96) NOT NULL,
  `user_id` bigint(20) unsigned NOT NULL,
  `key_kind` varchar(16) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_ob_vehicle_key` (`vehicle_identity`,`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=232 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_vehicle_keys omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_vehicle_maintenance
CREATE TABLE IF NOT EXISTS `ob_vehicle_maintenance` (
  `plate` varchar(16) NOT NULL,
  `mileage` decimal(12,2) NOT NULL DEFAULT 0.00,
  `fuel` decimal(6,2) NOT NULL DEFAULT 100.00,
  `oil_km` decimal(12,2) NOT NULL DEFAULT 0.00,
  `brake_km` decimal(12,2) NOT NULL DEFAULT 0.00,
  `spark_km` decimal(12,2) NOT NULL DEFAULT 0.00,
  `misfuel_liters` decimal(8,2) NOT NULL DEFAULT 0.00,
  `misfuel_type` varchar(16) DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_vehicle_maintenance omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_vehicle_tax_payments
CREATE TABLE IF NOT EXISTS `ob_vehicle_tax_payments` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `vehicle_id` int(10) unsigned NOT NULL,
  `owner_user_id` bigint(20) unsigned NOT NULL,
  `plate` varchar(16) NOT NULL,
  `amount` int(10) unsigned NOT NULL,
  `previous_due_at` datetime DEFAULT NULL,
  `next_due_at` datetime NOT NULL,
  `paid_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ob_vehicle_tax_owner` (`owner_user_id`),
  KEY `idx_ob_vehicle_tax_vehicle` (`vehicle_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_vehicle_tax_payments omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_vehicle_tax_repossessions
CREATE TABLE IF NOT EXISTS `ob_vehicle_tax_repossessions` (
  `vehicle_id` int(10) unsigned NOT NULL,
  `owner_user_id` bigint(20) unsigned NOT NULL,
  `plate` varchar(16) NOT NULL,
  `snapshot` longtext NOT NULL,
  `removed_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`vehicle_id`),
  KEY `idx_tax_repossessed_plate` (`plate`,`owner_user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_vehicle_tax_repossessions omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_vehicles
CREATE TABLE IF NOT EXISTS `ob_vehicles` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `owner_user_id` bigint(20) unsigned NOT NULL,
  `plate` varchar(16) NOT NULL,
  `model` varchar(64) NOT NULL,
  `label` varchar(96) NOT NULL,
  `garage` varchar(48) NOT NULL DEFAULT 'central',
  `stored` tinyint(1) NOT NULL DEFAULT 1,
  `fuel` decimal(6,2) NOT NULL DEFAULT 100.00,
  `body` decimal(7,2) NOT NULL DEFAULT 1000.00,
  `engine` decimal(7,2) NOT NULL DEFAULT 1000.00,
  `properties` longtext DEFAULT NULL,
  `purchase_price` bigint(20) unsigned NOT NULL DEFAULT 0,
  `vehicle_type` varchar(16) NOT NULL DEFAULT 'personal',
  `tax_rate` decimal(6,3) DEFAULT NULL,
  `tax_exempt` tinyint(1) NOT NULL DEFAULT 0,
  `acquired_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `tax_due_at` datetime DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_ob_vehicles_plate` (`plate`),
  KEY `idx_ob_vehicles_owner` (`owner_user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=232 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_vehicles omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_weapon_registry
CREATE TABLE IF NOT EXISTS `ob_weapon_registry` (
  `serial` varchar(64) NOT NULL,
  `item_name` varchar(64) NOT NULL,
  `purchaser_user_id` varchar(64) NOT NULL,
  `purchaser_name` varchar(100) NOT NULL,
  `shop_id` varchar(64) NOT NULL,
  `purchased_at` datetime NOT NULL,
  PRIMARY KEY (`serial`),
  KEY `idx_ob_weapon_registry_owner` (`purchaser_user_id`),
  KEY `idx_ob_weapon_registry_item` (`item_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Dados de ob_weapon_registry omitidos da distribuicao publica (dados operacionais ou pessoais).

-- Copiando estrutura para tabela orcore.ob_world_blips
CREATE TABLE IF NOT EXISTS `ob_world_blips` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `label` varchar(80) NOT NULL,
  `sprite` smallint(5) unsigned NOT NULL DEFAULT 1,
  `color` smallint(5) unsigned NOT NULL DEFAULT 3,
  `scale` decimal(4,2) NOT NULL DEFAULT 0.80,
  `x` decimal(12,4) NOT NULL,
  `y` decimal(12,4) NOT NULL,
  `z` decimal(12,4) NOT NULL,
  `short_range` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- Copiando dados para a tabela orcore.ob_world_blips: ~8 rows (aproximadamente)
INSERT INTO `ob_world_blips` (`id`, `label`, `sprite`, `color`, `scale`, `x`, `y`, `z`, `short_range`, `created_at`) VALUES
	(2, 'LSPD', 137, 38, 0.80, 424.1934, -980.0176, 30.6952, 1, '2026-08-29 23:21:28'),
	(3, 'Los Santos Customs', 402, 28, 0.80, -362.4528, -132.6066, 38.6652, 1, '2026-08-30 08:05:07'),
	(4, 'Benny\'s', 402, 1, 0.80, -206.0044, -1303.3319, 31.2513, 1, '2026-08-30 08:06:34'),
	(5, 'HP', 61, 2, 0.70, 292.1275, -584.1495, 43.1809, 1, '2026-09-09 13:03:37'),
	(6, 'Armeiro', 156, 3, 0.80, 1555.8198, -2174.0571, 77.3861, 1, '2026-10-20 15:04:04'),
	(7, 'Laboratorio clandestino', 499, 5, 0.80, 1390.5494, 3608.3340, 38.9348, 1, '2026-10-20 20:11:39'),
	(8, 'Oficina de montagem', 544, 1, 0.80, 1172.4659, 2637.7451, 37.7891, 1, '2026-10-20 21:12:37'),
	(9, 'Lavagem Dinheiro', 277, 28, 0.80, 132.8308, -3180.4746, 5.8418, 1, '2026-10-26 21:54:09');

/*!40103 SET TIME_ZONE=IFNULL(@OLD_TIME_ZONE, 'system') */;
/*!40101 SET SQL_MODE=IFNULL(@OLD_SQL_MODE, '') */;
/*!40014 SET FOREIGN_KEY_CHECKS=IFNULL(@OLD_FOREIGN_KEY_CHECKS, 1) */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40111 SET SQL_NOTES=IFNULL(@OLD_SQL_NOTES, 1) */;
