# Diagrama de la Máquina de Estados Finita (FSM) - Bot de Mantenimiento

```mermaid
stateDiagram-v2
    direction TB

    [*] --> ESPERA : Inicialización del Nivel
    ESPERA --> PATRULLA : Clic en EJECUTAR
    
    state PATRULLA {
        [*] --> MoverAPunto : Avanza hacia punto de patrulla
        MoverAPunto --> SiguientePunto : Distancia a punto menor a 20px
        SiguientePunto --> MoverAPunto : Selecciona siguiente punto
    }

    PATRULLA --> PERSEGUIR : Spark entra en visión (distancia <= 250px)
    BUSCAR --> PERSEGUIR : Spark reaparece en visión (distancia <= 250px)

    state PERSEGUIR {
        [*] --> PerseguirSpark : Persigue la posición en vivo de Spark
        PerseguirSpark --> GuardarMemoria : Registra última posición conocida
    }

    PERSEGUIR --> BUSCAR : Spark sale de visión (distancia > 250px)

    state BUSCAR {
        [*] --> InvestigarUltimaPosicion : Se desplaza a última posición conocida
        InvestigarUltimaPosicion --> EvaluarLlegada : Llegada a punto investigado
    }

    BUSCAR --> PATRULLA : Llega a última posición sin ver a Spark
    PERSEGUIR --> GAMEOVER : Bot captura a Spark (distancia <= 20px)

    state GAMEOVER {
        [*] --> DetenerSimulacion : Muestra modal GAME OVER
    }

    GAMEOVER --> ESPERA : Clic en REINTENTAR
```

## Resumen de Estados

1. **`ESPERA`**: Simulación pausada. Espera a que el jugador arme su secuencia y haga clic en **`EJECUTAR`**.
2. **`PATRULLA`**: El robot navega autónomamente entre los puntos de control de la estación espacial ($100\text{px/s}$).
3. **`PERSEGUIR`**: Spark entra en la zona de visión ($250\text{px}$). El robot persigue su posición en vivo ($180\text{px/s}$).
4. **`BUSCAR`**: Spark sale del área de visión. El robot se desplaza a la última posición conocida. Al llegar ($\le 20\text{px}$) sin ver a Spark, retorna a **`PATRULLA`**.
5. **`GAMEOVER`**: El robot alcanza a Spark ($\le 20\text{px}$). La simulación se detiene y se muestra la ventana emergente de Game Over.
