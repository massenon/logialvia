<?php

namespace Database\Seeders;

use App\Support\Droits;
use Illuminate\Database\Seeder;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Spatie\Permission\PermissionRegistrar;

/** 4 roles (DV-07) et leurs droits ; l'administrateur les recoit tous. */
class RolesAndPermissionsSeeder extends Seeder
{
    public function run(): void
    {
        app(PermissionRegistrar::class)->forgetCachedPermissions();

        foreach (config('logialvia.permissions') as $nom) {
            Permission::findOrCreate($nom, 'web');
        }

        foreach (array_keys(config('logialvia.roles')) as $nom) {
            $role = Role::findOrCreate($nom, 'web');
            $role->syncPermissions(Droits::permissionsDuRole($nom));
        }
    }
}
