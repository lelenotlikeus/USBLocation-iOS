# USBLocation Mobile · iOS

Versione nativa iPhone/iPad, separata da [USBLocation Windows](https://github.com/lelenotlikeus/USBLocation). Derivata da **Locus 1.0.2**, con attribuzione e licenza MIT conservate.

Mappa MapKit, teletrasporto, joystick 360°, velocità personalizzata, percorsi con distanza totale, pausa/ripresa, GPX, preferiti e pairing sul telefono dove supportato. Il backend usa realmente i servizi developer iOS tramite **idevice**: non è una mappa con un indicatore finto.

## Installazione

Il file `USBLocation-Mobile-1.0.1-unsigned.ipa` è da importare nel sistema di firma/sideload che utilizzi già. **Non è firmato dal progetto e non si installa con il solo download da Safari.** Non sono necessari certificati o password Apple nei sorgenti o nella CI.

- [Istruzioni passo passo](SETUP.md)
- [Build e test](https://github.com/lelenotlikeus/USBLocation-iOS/actions/workflows/build-ios.yml)
- [Release IPA](https://github.com/lelenotlikeus/USBLocation-iOS/releases)

## Requisiti reali

| Requisito | Dettaglio |
| --- | --- |
| Sistema | iOS/iPadOS 18+; pairing sul dispositivo previsto da iOS 27 |
| Installazione | Un metodo di firma e installazione IPA; durata/rinnovi dipendono dal metodo usato |
| Autorizzazione | Modalità sviluppatore, consenso rete locale e pairing confermato dall'utente |
| Tunnel | LocalDevVPN configurato e connesso; indirizzo predefinito `10.7.0.1` |
| Servizi developer | Developer Disk Image disponibile. Questa build delega la preparazione DDI a **StikDebug sul telefono**; non implementa un montaggio autonomo delle nuove Cryptex DDI |
| Rete | Avvio iniziale su Wi-Fi; MapKit usa i servizi Apple per mappe, ricerca e percorsi |

Su iOS 18–26 il pairing iniziale può richiedere un computer. Su iOS 27 è implementato il flusso “Pair on this iPhone”, basato sul consenso in Modalità sviluppatore. L'app non aggira pairing, firma o autorizzazioni.

## Uso

1. Completa il setup di [SETUP.md](SETUP.md). Ferma la simulazione e chiudi la versione Windows prima del test mobile.
2. Tocca la mappa oppure cerca un luogo. Premi **Teleport** per inviare la selezione. In Settings trovi anche coordinate manuali e l'opzione di teletrasporto immediato al tocco.
3. Imposta la velocità in **km/h** (0,1–300), poi premi **Fine** accanto al campo per nascondere la tastiera e ritrovare i controlli. Apri **Joy** e trascina il pad. Il rilascio azzera il movimento; cambiare app interrompe il joystick manuale.
4. Per un percorso apri il controllo del tracciato. Puoi calcolare un percorso MapKit, disegnarlo o importare GPX. Disattiva “Percorri il tracciato una volta” per scegliere i chilometri totali; la marcia inverte direzione alle estremità fino all'obiettivo.
5. **Pausa/Riprendi** conserva il progresso; **Ferma movimento** conserva la posizione simulata.
6. **Reset**, o “Invia Reset GPS” nelle impostazioni, invia la fine simulazione. Controlla il ritorno alla posizione reale su Mappe.

Le coordinate e i contatori avanzano dopo l'esito del backend. Le richieste sono serializzate fuori dal thread UI; il reset impedisce a una vecchia risposta di riattivare lo stato della sessione. Una richiesta già inviata può comunque completarsi prima del reset.

## Limiti e verifica

L'utente ha confermato il funzionamento della precedente build 1.0.0 sul proprio iPhone. La correzione della tastiera in 1.0.1 richiede una nuova prova sul telefono. La CI compila un eseguibile arm64 reale e un'IPA, verifica 90 casi geografici contro GeographicLib ed esegue test del controller/GPX con backend mock nel simulatore; non modifica alcun telefono e non verifica i tocchi sulla tastiera.

- Il protocollo di reset non certifica il fix GPS fisico.
- Background e durata della connessione dipendono da iOS; nessuna promessa di esecuzione illimitata dopo blocco schermo/chiusura forzata.
- Il joystick è utilizzabile dentro USBLocation. Le API pubbliche iOS non offrono una finestra interattiva sopra altre app; anche [Picture in Picture non riceve tocchi sui pulsanti personalizzati](https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-for-video-calls). Per osservare il movimento in un'altra app, avvia prima un percorso automatico; resta soggetto ai limiti di background di iOS.
- Riprepara i servizi developer se il dispositivo li perde, per esempio dopo un riavvio. La preparazione DDI non è contenuta in questa app.
- GPX: massimo 5 MB e 2.000 punti; XML con DTD/entità rifiutato. Percorsi quasi antipodali richiedono una tappa intermedia.
- MapKit non garantisce percorsi ciclabili dedicati: l'opzione Cycle usa il trasporto stradale disponibile.
- Non sono presenti bypass dei controlli di altre app o promesse di invisibilità.

## Sviluppo

Serve un Mac con Xcode 26+ e XcodeGen. La CI usa Xcode 26.3 su un runner macOS GitHub. Su Windows puoi modificare i sorgenti, ma Xcode non è disponibile.

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project USBLocation.xcodeproj -scheme USBLocation -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Per firmare localmente configura il tuo team Apple in Xcode. Non condividere certificati privati, profili di provisioning, record di pairing o password nel repository. I test del controller compilano una variante con backend finto separata dall'app reale; il backend di prova non è incluso nell'IPA.

## Licenza e provenienza

MIT; copyright upstream conservato in [LICENSE](LICENSE). Crediti, versioni e hash del backend nativo: [THIRD_PARTY.md](THIRD_PARTY.md). Il progetto non è affiliato a Locus, StikDebug o Apple. Nessuna telemetria aggiunta; MapKit e la preparazione developer possono comunicare con servizi Apple. I record di pairing sono credenziali locali e non vanno pubblicati.
