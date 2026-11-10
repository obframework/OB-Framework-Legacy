const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'..'),scripts=path.resolve(root,'..'),resources=path.resolve(scripts,'..');
const read=p=>fs.readFileSync(p,'utf8');
const checks=[
  [read(path.join(root,'config.lua')),/drug_sale\s*=\s*{/, 'tipo drug_sale'],
  [read(path.join(root,'config.lua')),/gunshot\s*=\s*{/, 'tipo gunshot'],
  [read(path.join(root,'config.lua')),/medical_emergency\s*=\s*{/, 'tipo medico'],
  [read(path.join(root,'config.lua')),/phone_police\s*=\s*{[\s\S]*?exclusive\s*=\s*true/, 'chamado policial exclusivo'],
  [read(path.join(root,'config.lua')),/phone_medical\s*=\s*{[\s\S]*?groups\s*=\s*{\s*'ambulance'\s*}/, 'chamado medico para ambulance'],
  [read(path.join(root,'server','main.lua')),/exports\('CreateAlert'/, 'export CreateAlert'],
  [read(path.join(root,'server','main.lua')),/Callback\.register\('acceptCall'/, 'aceite exclusivo no servidor'],
  [read(path.join(root,'server','main.lua')),/Callback\.register\('phoneRequest'/, 'chamado originado pelo telefone'],
  [read(path.join(root,'client','phone.lua')),/exports\.ob_phone:AddApp\(app\)/, 'aplicativo registrado no ob_phone'],
  [read(path.join(root,'server','main.lua')),/belongsToAny\(src, settings\.ignoreOnDutyGroups\)/, 'exclusao policial em servico'],
  [read(path.join(scripts,'ob_drugselling','server','main.lua')),/CreateAlert\('drug_sale'/, 'integracao de drogas'],
  [read(path.join(resources,'[system]','ob_vehiclekeys','server.lua')),/CreateAlert\('lockpick_vehicle'/, 'integracao de veiculo'],
  [read(path.join(resources,'[system]','ob_police','server','main.lua')),/CreateAlert\('lockpick_restraint'/, 'integracao de algema'],
];
let failed=false;
for(const [content,pattern,label] of checks){if(!pattern.test(content)){console.error('FALHOU:',label);failed=true}else console.log('OK:',label)}
if(failed)process.exit(1);
