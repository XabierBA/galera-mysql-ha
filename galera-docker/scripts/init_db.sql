-- ======================================
-- REINICIALIZACIÓN COMPLETA DE LA BASE
-- ======================================

DROP DATABASE IF EXISTS olimpiadas;
CREATE DATABASE olimpiadas;
USE olimpiadas;

SET FOREIGN_KEY_CHECKS = 0;

-- Eliminación de tablas en orden seguro
DROP TABLE IF EXISTS EVENTO;
DROP TABLE IF EXISTS MEDALLA;
DROP TABLE IF EXISTS PSICOLOGO;
DROP TABLE IF EXISTS ENTRENADOR;
DROP TABLE IF EXISTS FISIOTERAPEUTA;
DROP TABLE IF EXISTS CUERPO_TECNICO;
DROP TABLE IF EXISTS EQUIPO;
DROP TABLE IF EXISTS ATLETA;
DROP TABLE IF EXISTS PARTICIPANTE;
DROP TABLE IF EXISTS DISCIPLINA;
DROP TABLE IF EXISTS DEPORTE;
DROP TABLE IF EXISTS SEDE;
DROP TABLE IF EXISTS PAIS;

SET FOREIGN_KEY_CHECKS = 1;

-- ======================================
-- CREACIÓN DE TABLAS
-- ======================================

CREATE TABLE PAIS(
  cod_iso VARCHAR(3) PRIMARY KEY,
  nombre VARCHAR(50)
);

CREATE TABLE SEDE(
  id_sede INT PRIMARY KEY,
  nombre VARCHAR(50),
  ciudad VARCHAR(50),
  aforo INT,
  cod_iso VARCHAR(3),
  anho INT,
  FOREIGN KEY (cod_iso) REFERENCES PAIS(cod_iso)
);

CREATE TABLE DEPORTE(
  id_deporte INT PRIMARY KEY,
  nombre VARCHAR(50)
);

CREATE TABLE DISCIPLINA(
  id_deporte INT,
  id_disciplina INT,
  nombre VARCHAR(50),
  categoria CHAR(1),
  PRIMARY KEY(id_deporte, id_disciplina),
  FOREIGN KEY(id_deporte) REFERENCES DEPORTE(id_deporte)
);

CREATE TABLE PARTICIPANTE(
  id_participante INT PRIMARY KEY,
  nombre VARCHAR(50),
  tipo VARCHAR(10),
  cod_iso VARCHAR(3),
  FOREIGN KEY(cod_iso) REFERENCES PAIS(cod_iso)
);

CREATE TABLE ATLETA(
  dni VARCHAR(9) PRIMARY KEY,
  edad INT,
  genero CHAR(1),
  id_participante INT,
  FOREIGN KEY(id_participante) REFERENCES PARTICIPANTE(id_participante)
);

CREATE TABLE EQUIPO(
  id_equipo INT PRIMARY KEY,
  id_participante INT,
  FOREIGN KEY(id_participante) REFERENCES PARTICIPANTE(id_participante)
);

CREATE TABLE CUERPO_TECNICO(
  id_cuerpotec INT PRIMARY KEY,
  dni VARCHAR(9),
  id_participante INT,
  FOREIGN KEY(id_participante) REFERENCES PARTICIPANTE(id_participante)
);

CREATE TABLE FISIOTERAPEUTA(
  id_fisio INT PRIMARY KEY,
  titulacion VARCHAR(50),
  id_cuerpotec INT,
  FOREIGN KEY(id_cuerpotec) REFERENCES CUERPO_TECNICO(id_cuerpotec)
);

CREATE TABLE ENTRENADOR(
  id_entrenador INT PRIMARY KEY,
  especialidad VARCHAR(50),
  id_cuerpotec INT,
  FOREIGN KEY(id_cuerpotec) REFERENCES CUERPO_TECNICO(id_cuerpotec)
);

CREATE TABLE PSICOLOGO(
  id_psicologo INT PRIMARY KEY,
  licencia VARCHAR(50),
  id_cuerpotec INT,
  FOREIGN KEY(id_cuerpotec) REFERENCES CUERPO_TECNICO(id_cuerpotec)
);

CREATE TABLE MEDALLA(
  id_medalla INT PRIMARY KEY,
  tipo VARCHAR(50)
);

CREATE TABLE EVENTO(
    fecha DATE,
    id_deporte INT,
    id_disciplina INT,
    id_sede INT,
    id_medalla INT,
    id_participante INT,
    PRIMARY KEY(id_sede, id_deporte, id_disciplina, id_participante),
    FOREIGN KEY(id_deporte, id_disciplina) REFERENCES DISCIPLINA(id_deporte, id_disciplina),
    FOREIGN KEY(id_sede) REFERENCES SEDE(id_sede),
    FOREIGN KEY(id_participante) REFERENCES PARTICIPANTE(id_participante),
    FOREIGN KEY(id_medalla) REFERENCES MEDALLA(id_medalla)
);
