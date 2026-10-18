# USBLocation Mobile: installazione e primo teletrasporto

## 1. Installa l'IPA con il tuo metodo di firma

1. Scarica `USBLocation-Mobile-1.0.0-unsigned.ipa` dalla release o dall'artefatto della build.
2. Importalo nel tuo sistema di firma/sideload e installalo come una normale IPA. Un file scaricato ma non firmato non è installabile direttamente.
3. Se il metodo richiede conferma dell'autore o Modalità sviluppatore, completala nelle impostazioni iOS. Firma, rinnovi e numero di app disponibili dipendono dal tuo metodo; l'app non li aggira.
4. Apri USBLocation. Bundle ID sorgente: `io.github.lelenotlikeus.usblocation`; il tuo firmatario può modificarlo.

## 2. Attiva i prerequisiti sul telefono

- Attiva **Impostazioni → Privacy e sicurezza → Modalità sviluppatore**, riavvia e conferma.
- Installa e configura [LocalDevVPN](https://apps.apple.com/app/id6755608044). Consenti la creazione della VPN e connettila. L'app usa il tunnel esterno, senza richiedere entitlement VPN a pagamento propri.
- Se il servizio developer non è disponibile, prepara la DDI con [StikDebug](https://github.com/StikDebug/StikDebug), installato usando il tuo metodo di sideload. La procedura è descritta sotto. Non serve eseguire la funzione JIT di StikDebug per usare USBLocation.

## 3. Pairing direttamente sull'iPhone: iOS 27

1. In USBLocation apri **Settings → Pair on this iPhone**.
2. Avvia il pairing e consenti l'accesso alla **rete locale**. Consenti le notifiche se vuoi vedere il PIN quando passi alle impostazioni.
3. Lascia l'app in esecuzione e apri **Impostazioni → Privacy e sicurezza → Modalità sviluppatore → Pair with Host**.
4. Seleziona **USBLocation** e conferma il pairing. Inserisci il codice di sblocco quando richiesto da iOS.
5. Inserisci il codice a sei cifre mostrato da USBLocation quando iOS chiede il PIN del pairing.
6. Torna nell'app e attendi l'esito. Il file RPPairing viene conservato nel contenitore dell'app.

Questo flusso è implementato sulla base di Locus/idevice e va verificato sulla specifica build iOS. Se l'host non compare, controlla il consenso alla rete locale, Modalità sviluppatore e la versione iOS. Un'app sospesa o chiusa forzatamente non può completare il pairing.

### iOS 18–26

Su queste versioni può servire un pairing iniziale da computer tramite [idevice_pair](https://github.com/jkcoxson/idevice_pair), in modalità **RPPairing**. Importa poi il file da Settings oppure condividilo con USBLocation. I vecchi file lockdown di SideStore non sono intercambiabili con RPPairing; l'importazione viene validata dal parser idevice.

## 4. Disponibilità della Developer Disk Image

Il pairing e il tunnel non garantiscono che il servizio di simulazione sia già disponibile.

Questa build **non scarica/monta autonomamente le DDI**. Se il servizio non è pronto:

1. In Settings di USBLocation usa **Esporta pairing per StikDebug** e trasferisci il file a StikDebug, tramite la condivisione locale o File. È una credenziale: non inviarlo a siti o repository pubblici.
2. In StikDebug importa un RPPairing valido per questo stesso iPhone e completa la preparazione/download/montaggio della Developer Disk Image proposta dalla sua versione. Per iOS 26.4+ e 27 serve il percorso Cryptex supportato dalle versioni recenti di StikDebug.
3. Attendi l'esito positivo della preparazione, lascia LocalDevVPN connesso e torna in USBLocation.
4. Se StikDebug non riesce a preparare i servizi sulla tua build iOS, non considerare pronta la simulazione: conserva l'errore e segnala la versione usata. Non viene proposto un bypass alternativo.

La disponibilità può essere persa dopo un riavvio del telefono. Se i servizi sono già stati preparati, questo passaggio può non essere necessario. Il percorso desktop precedente non deve restare collegato durante l'uso mobile.

## 5. Primo test

1. Invia Reset e chiudi USBLocation Windows prima di usare il nuovo client.
2. Per la prima connessione usa Wi-Fi con LocalDevVPN attivo; IP predefinito `10.7.0.1` in Settings.
3. Tocca una posizione sulla mappa e premi **Teleport**.
4. Attendi l'esito. Uno stato di connessione o la presenza del PIN non sono una conferma GPS.
5. Apri Mappe sul telefono e verifica lo spostamento. Torna in USBLocation per provare Joy, velocità e percorsi.
6. Concludi con **Reset** e verifica il ritorno al fix reale. Se non torna, riprova con il tunnel attivo e, se necessario, riavvia l'iPhone.

## Se il processo viene interrotto

- Una richiesta in corso può terminare dopo il rilascio del joystick.
- iOS può sospendere o terminare l'app in background: non viene garantita una sessione infinita.
- Se la rete o il servizio falliscono, il movimento si ferma e viene mostrato l'errore. Non viene dichiarato un ripristino fisico verificato.
- Se la firma dell'app scade, il rinnovo dipende dal tuo firmatario; USBLocation non fornisce una firma permanente.

## Dati e privacy

Pairing, preferiti e cronologia sono locali al telefono. L'importazione pairing verifica il formato prima di sostituire il file e usa scrittura atomica. I pairing importati vengono esclusi dal backup; i pairing prodotti dal flusso on-device mantengono la gestione upstream e non vengono esportati automaticamente. MapKit contatta Apple per mappe, ricerca e percorsi. Non sono aggiunti account, analisi d'uso o invii della cronologia a nostri server.
