Config = {
    MinimumPolice=0, PolicePermissions={'police'}, InteractDistance=2.5,
    CooldownSeconds=900, GlobalCooldownSeconds=30, RobberySeconds=240,
    LootSeconds=8, RewardItem='black_money', Reward={min=500,max=1500}, AlertSeconds=120,
    EditorPermission='world.shops', EditorAce='or.admin', MaxRegisters=300,
    RegisterItem='lockpick', RegisterSeconds=12,
    -- Exemplos sobre registradoras ja existentes. O editor F11 salva em KVP;
    -- exclusoes tambem persistem. Nao apague server-data/db ao migrar a base.
    Locations={
        strawberry={label='Registradora Strawberry',coords={x=24.95,y=-1344.95,z=29.50}},
        little_seoul={label='Registradora Little Seoul',coords={x=-706.10,y=-915.43,z=19.22}},
    },
}
for _,location in pairs(Config.Locations) do
    local p=location.coords
    location.radius=8
    location.steps={{label='Arrombar registradora',item=Config.RegisterItem,consume=true,seconds=Config.RegisterSeconds,
        game='Keypress',options={steps=3,speed=1.0,tolerance=0.12}}}
    location.loot={{x=p.x,y=p.y,z=p.z,model='prop_cash_pile_01'}}
end
