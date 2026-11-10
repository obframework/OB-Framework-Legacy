Config = {
    MinimumPolice=3, PolicePermissions={'police'}, InteractDistance=2.8,
    CooldownSeconds=900, GlobalCooldownSeconds=420, RobberySeconds=600,
    LootSeconds=15, RewardItem='black_money', Reward={min=4500,max=9000}, AlertSeconds=180,
    Locations={},
}
-- Apenas locais e faixas de premio tomados como referencia do orbis-storeheist.
local stores = {
    {id='ammunation_1',label='Ammu-Nation Cypress',x=813.91,y=-2154.4241,z=29.619,gun=true},
    {id='ammunation_2',label='Ammu-Nation Pillbox',x=17.5316,y=-1108.4236,z=29.797,gun=true},
    {id='store_1',label='Deposito Strawberry',x=30.2836,y=-1339.2946,z=29.4971},
    {id='store_2',label='Deposito Little Seoul',x=-709.6741,y=-905.4037,z=19.2156},
}
for _,row in ipairs(stores) do
    local p={x=row.x,y=row.y,z=row.z}
    Config.Locations[row.id]={label=row.label,coords=p,radius=15,
        reward=row.gun and {min=12000,max=18000} or {min=4500,max=9000},
        steps={
            {label='Invadir seguranca do estabelecimento',coords=p,item='heist_laptop',consume=false,seconds=30,
                game='DataCrack',options={bars=5,timeSeconds=50,maxMistakes=3}},
            {label='Abrir cofre do deposito',coords=p,item='heist_drill',consume=false,seconds=150,
                game='Circuit',options={rows=3,timeSeconds=60,maxAttempts=3},
                animation={dict='anim@heists@fleeca_bank@drilling',clip='drill_straight_idle',flag=49}},
        },
        loot={{x=p.x,y=p.y,z=p.z-0.8,model='prop_cash_pile_01'}},
    }
end
