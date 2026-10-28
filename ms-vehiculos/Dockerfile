# syntax=docker/dockerfile:1

# =============================================================================
# Etapa 1 - build: compila el jar con el JDK completo (no llega a la imagen final)
# =============================================================================
FROM eclipse-temurin:21-jdk-alpine-3.24 AS build
WORKDIR /workspace

# Primero solo lo necesario para resolver dependencias: esta capa queda en cache
# mientras no cambie el pom.xml, y los builds siguientes no descargan nada.
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN chmod +x mvnw && ./mvnw -B -ntp -q dependency:go-offline

COPY src/ src/
# Las pruebas ya corrieron en el job de CI; aqui solo se empaqueta.
RUN ./mvnw -B -ntp -q package -DskipTests \
 && cp target/*.jar application.jar \
 && java -Djarmode=tools -jar application.jar extract --layers --destination extracted \
 && mkdir -p extracted/dependencies extracted/spring-boot-loader \
             extracted/snapshot-dependencies extracted/application

# =============================================================================
# Etapa 2 - runtime: solo JRE sobre Alpine, usuario sin privilegios
# =============================================================================
FROM eclipse-temurin:21-jre-alpine-3.24 AS runtime

LABEL org.opencontainers.image.title="ms-vehiculos" \
      org.opencontainers.image.description="Microservicio CRUD de vehiculos (Spring Boot 3.5, Java 21)" \
      org.opencontainers.image.source="https://github.com/chelo11/EVA_N2"

# Parches de seguridad del sistema operativo publicados despues de la imagen base.
# UID/GID numericos: Kubernetes puede verificar runAsNonRoot sin ambiguedad.
RUN apk upgrade --no-cache \
 && addgroup -S -g 10001 app \
 && adduser -S -D -H -u 10001 -G app -s /sbin/nologin app

WORKDIR /app

# Capas de Spring Boot ordenadas de la que menos cambia a la que mas cambia:
# un cambio de codigo solo reemplaza la ultima capa (pocos KB).
COPY --from=build --chown=10001:10001 /workspace/extracted/dependencies/ ./
COPY --from=build --chown=10001:10001 /workspace/extracted/spring-boot-loader/ ./
COPY --from=build --chown=10001:10001 /workspace/extracted/snapshot-dependencies/ ./
COPY --from=build --chown=10001:10001 /workspace/extracted/application/ ./

USER 10001:10001

# JVM consciente de los limites del contenedor (cgroups) y que muere ante OOM
# para que el orquestador la reinicie en vez de quedar en estado inestable.
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=60.0 -XX:+ExitOnOutOfMemoryError"

EXPOSE 9004

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
  CMD wget -qO- http://127.0.0.1:9004/actuator/health/liveness || exit 1

ENTRYPOINT ["java", "-jar", "application.jar"]
