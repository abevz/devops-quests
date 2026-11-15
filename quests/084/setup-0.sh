set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_SEED'
terraform {
 required_providers {
  docker = { source = "registry.terraform.io/kreuzwerker/docker", version = "3.6.2" }
 }
}
provider "docker" {}
locals { routes = ["south", "north"] }
resource "docker_container" "worker" {
 name = "rail-worker"
 image = "docker.io/library/busybox:1.37.0@sha256:66a6306db78bf2dbf3487f293aa8d6990d8e506fdffab9cc43fe422becf886e4"
 command = ["sleep", "36000"]
}
resource "docker_network" "backplane" { name = "rail-fabric" }
resource "docker_volume" "ledger" {
 count = length(local.routes)
 name = "rail-${local.routes[count.index]}-data"
}
resource "docker_container" "node" {
 count = length(local.routes)
 name = "rail-${local.routes[count.index]}"
 image = "docker.io/library/busybox:1.37.0@sha256:66a6306db78bf2dbf3487f293aa8d6990d8e506fdffab9cc43fe422becf886e4"
 command = ["sh", "-c", "test -s /data/ledger || printf '%s\\n' '${local.routes[count.index]}-retained' > /data/ledger; exec httpd -f -p 8080 -h /data"]
 networks_advanced { name = docker_network.backplane.name }
 volumes {
  volume_name = docker_volume.ledger[count.index].name
  container_path = "/data"
 }
}
DQ_SEED
tofu fmt
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
python3 - <<'DQ_IDENTITIES'
import hashlib,json,subprocess,time
from pathlib import Path

def inspect(*args):return json.loads(subprocess.check_output(['docker',*args],text=True))[0]
worker=inspect('inspect','rail-worker');network=inspect('network','inspect','rail-fabric')
facts={'worker_id':worker['Id'],'network_id':network['Id'],'routes':{}}
for route in ['north','south']:
 node=inspect('inspect','rail-'+route);volume=inspect('volume','inspect','rail-'+route+'-data')
 for attempt in range(50):
  response=subprocess.run(['docker','exec','rail-'+route,'wget','-qO-','http://127.0.0.1:8080/ledger'],capture_output=True)
  if response.returncode==0:
   data=response.stdout
   break
  time.sleep(.1)
 else:raise RuntimeError('Seeded ledger service did not become ready')
 facts['routes'][route]={'container_id':node['Id'],'volume_name':volume['Name'],'volume_created_at':volume['CreatedAt'],'data_sha256':hashlib.sha256(data).hexdigest()}
Path('original-id').write_text(worker['Id']+'\n')
Path('migration-identities.json').write_text(json.dumps(facts,indent=2)+'\n')
DQ_IDENTITIES
cat > module-contract.json <<'DQ_CONTRACT'
{
  "worker_address": "module.station.docker_container.worker",
  "worker_name": "rail-worker",
  "worker_output": "worker_id",
  "network_address": "module.fabric.docker_network.backplane",
  "network_name": "rail-fabric",
  "routes_output": "routes",
  "plan_file": "migration-plan.json",
  "routes": {
    "north": {
      "container_address": "module.route[\"north\"].docker_container.worker",
      "volume_address": "module.route[\"north\"].docker_volume.ledger",
      "container_name": "rail-north",
      "volume_name": "rail-north-data"
    },
    "south": {
      "container_address": "module.route[\"south\"].docker_container.worker",
      "volume_address": "module.route[\"south\"].docker_volume.ledger",
      "container_name": "rail-south",
      "volume_name": "rail-south-data"
    }
  },
  "meaning": {
    "en": "Refactor all six managed objects into the listed addresses. Retain the original live container and network IDs, existing volumes and their creation identity, ledger bytes and route correspondence. Each route workload keeps its own data volume and shared network. The worker output is its original ID; the routes output maps each route key to that original route container ID. The saved JSON plan has exactly these six managed entries, all no-op with original IDs before and after; unrelated managed entries are not allowed. Read-only data lookups are allowed. A fresh plan has no changes. Results do not establish command history or uninterrupted availability.",
    "ru": "Перенесите все шесть управляемых объектов на перечисленные адреса. Сохраните исходные ID живых контейнеров и сети, существующие тома и идентичность их создания, байты журналов и соответствие маршрутам. Каждый маршрут сохраняет свой том данных и общую сеть. Output worker содержит его исходный ID, output routes сопоставляет каждому ключу исходный ID контейнера маршрута. Сохранённый JSON-план содержит ровно эти шесть управляемых записей, все no-op с исходными ID до и после; посторонние управляемые записи недопустимы. Разрешены читающие data sources. Новый план не содержит изменений. Результат не устанавливает историю команд или непрерывную доступность.",
    "de": "Verschiebe alle sechs verwalteten Objekte an die aufgeführten Adressen. Behalte ursprüngliche Container- und Netzwerk-IDs, vorhandene Volumes und ihre Erstellungsidentität, Ledger-Bytes und Routenzuordnung. Jede Route behält ihr eigenes Datenvolume und das gemeinsame Netzwerk. Die Worker-Ausgabe enthält ihre ursprüngliche ID; routes ordnet jedem Routenschlüssel seine ursprüngliche Container-ID zu. Der gespeicherte JSON-Plan enthält genau diese sechs verwalteten Einträge, alle no-op mit ursprünglichen IDs davor und danach; fremde verwaltete Einträge sind unzulässig. Lesende Datenquellen sind erlaubt. Ein neuer Plan enthält keine Änderungen. Ergebnisse belegen weder Befehlsverlauf noch durchgehende Verfügbarkeit.",
    "es": "Traslada los seis objetos gestionados a las direcciones indicadas. Conserva los IDs originales de contenedores y red, los volúmenes existentes y su identidad de creación, los bytes de los registros y su relación con las rutas. Cada ruta conserva su propio volumen y la red compartida. La salida del worker contiene su ID original; routes asigna a cada clave el ID original de su contenedor. El plan JSON guardado contiene exactamente estas seis entradas gestionadas, todas no-op con los IDs originales antes y después; no se permiten entradas gestionadas ajenas. Se permiten consultas de datos de solo lectura. Un plan nuevo no tiene cambios. Los resultados no prueban el historial de comandos ni la disponibilidad continua.",
    "pl": "Przenieś wszystkie sześć zarządzanych obiektów pod wymienione adresy. Zachowaj pierwotne ID kontenerów i sieci, istniejące wolumeny i tożsamość ich utworzenia, bajty rejestrów i powiązanie z trasami. Każda trasa zachowuje własny wolumen i wspólną sieć. Wyjście worker zawiera jego pierwotne ID; routes przypisuje każdemu kluczowi pierwotne ID kontenera trasy. Zapisany plan JSON zawiera dokładnie te sześć zarządzanych wpisów, wszystkie no-op z pierwotnymi ID przed i po; obce zarządzane wpisy są niedozwolone. Dopuszczalne są źródła danych tylko do odczytu. Nowy plan nie zawiera zmian. Wyniki nie dowodzą historii poleceń ani ciągłej dostępności."
  }
}
DQ_CONTRACT
mkdir -p modules/station modules/fabric modules/route
