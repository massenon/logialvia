<?php

namespace App\Support;

/**
 * UUID deterministe (version 5, SHA-1) calcule depuis une cle metier, a l'IDENTIQUE du
 * poste (`uuidDeterministe` de `identifiant_poste.dart`) : meme cle, meme identifiant, sur
 * tous les postes et au serveur. Le test `GroupesTaxeTest` fige des valeurs calculees par le Dart.
 */
final class UuidDeterministe
{
    public static function de(string $cle): string
    {
        $octets = array_values(unpack('C16', substr(sha1('logialvia:'.$cle, true), 0, 16)));
        $octets[6] = ($octets[6] & 0x0F) | 0x50; // version 5
        $octets[8] = ($octets[8] & 0x3F) | 0x80; // variante RFC 4122
        $hex = implode('', array_map(fn (int $o) => str_pad(dechex($o), 2, '0', STR_PAD_LEFT), $octets));

        return substr($hex, 0, 8).'-'.substr($hex, 8, 4).'-'.substr($hex, 12, 4).'-'.substr($hex, 16, 4).'-'.substr($hex, 20);
    }
}
