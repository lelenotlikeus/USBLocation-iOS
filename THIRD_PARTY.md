# Provenienza e licenze

USBLocation Mobile deriva da [ChrisMack32/Locus](https://github.com/ChrisMack32/Locus), versione **1.0.2**, commit `d24e549e00ea9caad48dd737531040c042758af5`. La licenza MIT e il copyright dei collaboratori Locus sono conservati in `LICENSE`. L'interfaccia e il flusso pairing provengono da tale base; non sono presentati come un protocollo scritto da zero.

Modifiche di questo progetto: identità USBLocation, controlli velocità/distanza, WGS84, conteggio dopo l'esito del backend, Stop/Reset durante richieste pendenti, I/O nativo seriale asincrono, validazione pairing e GPX, test e pipeline IPA. La versione Windows mantiene il proprio repository e la propria licenza GPL.

## idevice

Backend [jkcoxson/idevice](https://github.com/jkcoxson/idevice), MIT, copyright Jackson Coxson; testo in `Vendor/idevice/LICENSE.txt`. Header e archivio statico provengono **senza modifiche** dalla versione Locus indicata sopra. La versione esatta del commit Rust usata dall'autore dell'archivio non è dichiarata nella base; questo progetto non inventa un numero di versione o una riproducibilità binaria.

- `idevice.h` SHA-256: `23b7a97ed37ebd9bc53e7620b9da8a9d1b5961f05252201462b7c5bd39e0fcc0`.
- `libidevice_ffi.a` SHA-256: `05e6f58f082ee9f866a60763debe9b016e003005d424ac227b8d459686a2b575`.

Sono usate le funzioni effettivamente dichiarate nell'header: `pairable_host_accept`, lettura/scrittura RPPairing, `tunnel_create_rppairing`, handshake/RemoteServer e `location_simulation_set/clear`. Gli handle nativi sono liberati nell'ordine delle dipendenze, dopo le chiamate serializzate. Nessun JIT, jailbreak, patch o exploit è introdotto dall'app.

## Altri componenti

- SwiftUI, MapKit, CoreLocation e SDK Apple: forniti dal sistema/SDK, con le condizioni Apple applicabili; nessun SDK Apple viene redistribuito nel repository.
- StikDebug e LocalDevVPN sono prerequisiti esterni, non incorporati nell'IPA. Si applicano le licenze e le condizioni dei rispettivi progetti.
- Logo USBLocation: asset originale della versione Windows, renderizzato in PNG per l'icona iOS.
- I dati geografici di riferimento nei test sono calcolati con GeographicLib WGS84 2.1; nessuna libreria Python è incorporata nell'app iOS.

Questa nota non è una certificazione della distribuzione o un audit delle dipendenze native precompilate.
