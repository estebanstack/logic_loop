# Diagramas de Arquitectura General - Logic Loop

## 1. Arquitectura General del Sistema

```mermaid
graph TD
    classDef mainNode fill:#1f2937,stroke:#3b82f6,stroke-width:2px,color:#fff;
    classDef agentNode fill:#1e3a8a,stroke:#60a5fa,stroke-width:2px,color:#fff;
    classDef playerNode fill:#064e3b,stroke:#34d399,stroke-width:2px,color:#fff;
    classDef objNode fill:#7c2d12,stroke:#fb923c,stroke-width:2px,color:#fff;
    classDef uiNode fill:#312e81,stroke:#a5b4fc,stroke-width:2px,color:#fff;

    Main["Main (Entorno de la Estación Espacial)"]:::mainNode
    Bot["Bot de Mantenimiento (Agente Autónomo IA)"]:::agentNode
    Spark["Spark (Agente Programable del Jugador)"]:::playerNode
    Target["Componente de Reparación (Objetivo)"]:::objNode
    UI["Interfaz de Usuario (Paneles de Depuración y Programación)"]:::uiNode

    Main -->|"1. Proporciona datos sensoriales"| Bot
    Main -->|"2. Administra posición y cuadrícula (64px)"| Spark
    Main -->|"3. Contiene estado del objetivo"| Target
    
    Player["Jugador"] -->|"4. Programa secuencia de comandos"| UI
    UI -->|"5. Envía cola de ejecución (EJECUTAR)"| Spark
    
    Bot -->|"6. Percibe posición dentro del radio de visión (250px)"| Main
    Bot -->|"7. Ejecuta ciclo PERCIBIR → DECIDIR → ACTUAR"| Bot
    
    Spark -->|"8. Ejecuta comandos paso a paso"| Main
    Spark -->|"9. Ejecuta INTERACTUAR cerca del objetivo"| Target
    
    Bot -->|"10. Si captura a Spark (<= 20px) -> ¡GAME OVER!"| Main
    Target -->|"11. Si se recolecta el componente -> ¡NIVEL COMPLETADO!"| Main
```

## 2. Ciclo PERCIBIR → DECIDIR → ACTUAR

```mermaid
graph LR
    classDef perceive fill:#1e3a8a,stroke:#60a5fa,stroke-width:2px,color:#fff;
    classDef decide fill:#581c87,stroke:#c084fc,stroke-width:2px,color:#fff;
    classDef act fill:#065f46,stroke:#34d399,stroke-width:2px,color:#fff;

    sub_perceive["1. PERCIBIR (perceive)"]:::perceive
    sub_decide["2. DECIDIR (decide)"]:::decide
    sub_act["3. ACTUAR (act)"]:::act

    sub_perceive -->|"Consulta Main.get_environment_info()"| sub_decide
    sub_decide -->|"Evalúa estado (PATRULLA / PERSEGUIR / BUSCAR)"| sub_act
    sub_act -->|"Aplica move_and_slide() y actualiza UI"| sub_perceive
```

## 3. Diagrama de Secuencia de Ejecución

```mermaid
sequenceDiagram
    autonumber
    actor Jugador
    participant UI as Panel de Programación
    participant Main as Main (Entorno)
    participant Spark as Spark (Dron)
    participant Bot as Bot de Mantenimiento

    Jugador->>UI: Construye programa (MOVER, GIRAR IZQ, GIRAR DER, INTERACTUAR)
    Jugador->>UI: Hace clic en EJECUTAR
    UI->>Main: start_simulation() (is_simulation_running = true)
    
    par Ejecución Concurrente Simultánea
        loop Cada paso del programa de Spark (step_delay = 0.45s)
            Spark->>Main: Avanza en la cuadrícula (64px)
            Main->>UI: Actualiza visualización [X] MOVER, [>] GIRAR DER, [ ] INTERACTUAR
        end
    and Ciclo Autónomo del Bot (Cada fotograma)
        Bot->>Main: perceive() -> Evalúa radio de visión (250px)
        alt Spark dentro de visión
            Bot->>Main: decide() -> Transición a PERSEGUIR
            Bot->>Spark: Se desplaza autónomamente hacia Spark
            opt Si el Bot alcanza a Spark (<= 20px)
                Bot->>Main: reset_spark() -> Muestra Modal de ¡GAME OVER!
            end
        else Spark fuera de visión
            Bot->>Main: decide() -> Transición a PATRULLA / BUSCAR
            Bot->>Main: Navega puntos de patrulla autónomamente
        end
    end

    opt Spark llega al Componente de Reparación y ejecuta INTERACTUAR
        Spark->>Main: check_interact() -> Muestra Modal de ¡NIVEL COMPLETADO!
    end
```

## 4. Paradigma 4: Cadenas de Markov (Clima Espacial y Radiación)

Proceso estocástico en tiempo discreto $\{X_t, t \ge 0\}$ con propiedad de Markov sobre el espacio de estados $S = \{\text{ESTABLE}, \text{FLUCTUANTE}, \text{CRÍTICO}\}$.

```mermaid
stateDiagram-v2
    direction LR

    [*] --> ESTABLE : Inicialización
    
    ESTABLE --> ESTABLE : P = 0.70
    ESTABLE --> FLUCTUANTE : P = 0.25
    ESTABLE --> CRÍTICO : P = 0.05
    
    FLUCTUANTE --> ESTABLE : P = 0.30
    FLUCTUANTE --> FLUCTUANTE : P = 0.50
    FLUCTUANTE --> CRÍTICO : P = 0.20
    
    CRÍTICO --> ESTABLE : P = 0.15
    CRÍTICO --> FLUCTUANTE : P = 0.35
    CRÍTICO --> CRÍTICO : P = 0.50
```

- **Distribución Estacionaria $\pi$**: Calculada mediante el método de potencias $\pi P = \pi \implies \pi \approx [0.453, 0.358, 0.189]$.
- **Impacto Físico**: Modula la tasa de recarga solar de Spark ($\times 1.0, \times 0.6, \times 0.2$) y la velocidad de alerta del Bot de Mantenimiento.

---

## 5. Paradigma 5: Modelos Ocultos de Markov (HMM - Diagnóstico Latente)

Tupla $\lambda = (A, B, \pi_0)$ para inferencia y filtrado sobre estados inobservables del núcleo de la estación.

```mermaid
graph TD
    subgraph Estados_Ocultos ["Estados Ocultos (Desgaste del Núcleo)"]
        H0["Óptimo"]
        H1["Degradado"]
        H2["Crítico"]
        H0 -->|"A[0,0]=0.75"| H0
        H0 -->|"A[0,1]=0.20"| H1
        H1 -->|"A[1,1]=0.70"| H1
        H1 -->|"A[1,2]=0.20"| H2
        H2 -->|"A[2,2]=0.80"| H2
    end

    subgraph Emisiones_Observables ["Señales de Telemetría (Sensores)"]
        O0["Verde (Nominal)"]
        O1["Amarillo (Vibración)"]
        O2["Rojo (Alarma)"]
    end

    H0 -.->|"B=0.70"| O0
    H0 -.->|"B=0.25"| O1
    H1 -.->|"B=0.60"| O1
    H1 -.->|"B=0.20"| O2
    H2 -.->|"B=0.70"| O2

    subgraph Algoritmos ["Inferencia y Decodificación"]
        Viterbi["Algoritmo de Viterbi: Secuencia Óptima X̂_{1:T}"]
        Forward["Filtro Forward: Creencia P(X_t | Y_{1:t})"]
    end
```

---

## 6. Paradigma 6: Teoría de Juegos (Interacción Estratégica)

Juego bimatriz $2 \times 2$ entre Spark (Dron) y Bot de Mantenimiento (Seguridad).

| Spark \ Bot | Patrulla Suave (0) | Escaneo Estricto (1) |
|:---|:---:|:---:|
| **Cauto / Stealth (0)** | $(3.0, 3.0)$ | $(1.0, 4.0)$ |
| **Audaz / Rush (1)** | $(4.0, 1.0)$ | $(0.0, 0.0)$ |

```mermaid
graph LR
    SparkChoice["Spark: {Cauto, Audaz}"] --> PayoffMatrix["Bimatriz de Pagos U(s_1, s_2)"]
    BotChoice["Bot: {Patrulla, Escaneo}"] --> PayoffMatrix
    
    PayoffMatrix --> PureNash["Equilibrios Puros: (Cauto, Escaneo) y (Audaz, Patrulla)"]
    PayoffMatrix --> MixedNash["Equilibrio Mixto: p* = 50%, q* = 50% | E[U] = (2.0, 2.0)"]
    PayoffMatrix --> StrategicModifiers["Modificadores en Simulación: Costo de Motores y Radio de Visión"]
```

