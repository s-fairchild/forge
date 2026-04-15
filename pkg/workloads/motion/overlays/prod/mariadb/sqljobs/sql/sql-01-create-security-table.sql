CREATE TABLE IF NOT EXISTS security (
  id BIGINT NOT NULL AUTO_INCREMENT,
  event_id VARCHAR(255) UNIQUE NOT NULL,
  camera INTEGER NOT NULL,
  time_stamp DATETIME NOT NULL,
  file_name VARCHAR(255),
  file_type VARCHAR(255),
  frame INTEGER,
  event_text VARCHAR(255) NOT NULL,
  event_end DATETIME,
  movie_end DATETIME,
  sound_alert_number INTEGER,
  sound_alert_name VARCHAR(255),
  sound_trigger_freq BIGINT,
  PRIMARY KEY (`id`, event_id)
);

DESCRIBE security;
