@props(['nom'])
{{-- Icone Material Symbols : <x-icone nom="egg" class="text-[20px]" />. Les noms viennent de config/icones.php (genere). --}}
<span {{ $attributes->class(['icone']) }} aria-hidden="true">{!! '&#x'.(config('icones.'.$nom) ?? 'e887').';' !!}</span>
