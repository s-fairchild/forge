CREATE TABLE IF NOT EXISTS security (
  id BIGINT NOT NULL AUTO_INCREMENT,
  camera INTEGER NOT NULL,
  filename VARCHAR(255) NOT NULL,
  file_type VARCHAR(255) NOT NULL,
  time_stamp DATETIME NOT NULL,
  frame INTEGER,
  motion_event INTEGER,
  text_event VARCHAR(255),
  movie_end DATETIME,
  PRIMARY KEY (`id`)
);

DESCRIBE security;
