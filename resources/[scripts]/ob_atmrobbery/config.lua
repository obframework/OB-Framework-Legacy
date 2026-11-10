Config = {
    MinimumPolice=0, PolicePermissions={'police'}, InteractDistance=2.8,
    CooldownSeconds=900, GlobalCooldownSeconds=300, RobberySeconds=300,
    LootSeconds=15, RewardItem='black_money', Reward={min=3500,max=9000}, AlertSeconds=180,
    -- Apenas ATMs cadastrados sao aceitos pelo servidor; nao confia em coords
    -- enviadas pelo cliente. Acrescente aqui os ATMs de seus mapas/MLOs.
    Locations={},
}
local machines = {
    {x=147.63,y=-1035.72,z=29.34}, {x=145.97,y=-1035.18,z=29.34},
    {x=117.02,y=-456.04,z=66.79}, {x=-1212.98,y=-330.84,z=37.79},
    {x=-1205.35,y=-325.58,z=37.87}, {x=-2962.58,y=482.63,z=15.70},
    {x=-2955.70,y=488.72,z=15.46}, {x=-3040.75,y=593.10,z=7.91},
    {x=-3241.10,y=997.60,z=12.55}, {x=1171.52,y=2702.57,z=38.18},
    {x=1735.24,y=6410.51,z=35.04}, {x=1701.21,y=6426.57,z=32.76},
    {x=-386.73,y=6045.95,z=31.50}, {x=-282.97,y=6226.10,z=31.49},
    {x=-57.65,y=-92.66,z=57.78}, {x=313.49,y=-280.54,z=54.17},
}
for index,point in ipairs(machines) do
    Config.Locations['atm_'..index]={label='ATM '..index,coords=point,radius=8,
        steps={{label='Preparando carga do ATM',item='dynamite',consume=true,seconds=20,game='Keypress',
            options={steps=3,speed=1.1,tolerance=0.12},explosive=true,fuseSeconds=10,
            animation={dict='anim@heists@ornate_bank@thermal_charge',clip='thermal_charge',flag=49}}},
        loot={{x=point.x,y=point.y,z=point.z-0.8,model='prop_cash_pile_01'}},
    }
end
