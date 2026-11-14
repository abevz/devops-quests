set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_PRODUCER'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
variable "release" {
 type = string
 default = "release-81"
}
resource "local_file" "release" {
 filename = "${path.root}/release.txt"
 content = "${var.release}\n"
}
resource "terraform_data" "producer" { input = "release-producer" }
output "release" { value = local_file.release.content }
output "producer_id" { value = terraform_data.producer.id }
DQ_PRODUCER
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
tofu output -json producer_id > producer-identity.json
mkdir -p modules/delivery
cat > modules/delivery/main.tf <<'DQ_MODULE'
variable "release" { type = string }
variable "producer_id" { type = string }
variable "targets" { type = set(string) }
output "contract" { value = {} }
DQ_MODULE
cat >> main.tf <<'DQ_DELIVERY'
module "delivery" {
 source = "./modules/delivery"
 release = "retired"
 producer_id = terraform_data.producer.id
 targets = ["app1", "app2", "app3"]
}
output "delivery" { value = module.delivery.contract }
DQ_DELIVERY
cat > delivery-schema.json <<'DQ_SCHEMA'
{
  "output": "delivery",
  "fields": [
    "release",
    "producer_id",
    "targets"
  ],
  "targets": [
    "app1",
    "app2",
    "app3"
  ],
  "receipt_fields": [
    "target",
    "release",
    "producer_id"
  ],
  "receipt_path": "/srv/site/delivery.json",
  "receipt_mode": "0644",
  "process_container": "worker",
  "process_environment": "DELIVERY_CONTRACT",
  "input": "release",
  "input_cases": [
    "release-81",
    "release-canary"
  ],
  "shape": {
    "release": "string",
    "producer_id": "string",
    "targets": {
      "<target>": {
        "target": "string",
        "release": "string",
        "producer_id": "string"
      }
    }
  },
  "meaning": {
    "en": "The release field equals the managed producer file without its final newline. The producer_id field is the persistent producer object identity and retains its initial value. The targets object has exactly the listed target keys. Each entry has target equal to its key and release and producer_id equal to the root fields. A receipt is that entry as JSON. The process environment contains the complete root object as JSON. Whitespace and JSON member order are not significant. Every input case must preserve these relationships without applying its plan.",
    "ru": "Поле release равно содержимому управляемого файла производителя без завершающего перевода строки. Поле producer_id — постоянная идентичность объекта производителя с сохранением исходного значения. Объект targets содержит ровно перечисленные ключи получателей. В каждой записи target равен её ключу, а release и producer_id — одноимённым корневым полям. Квитанция — эта запись в JSON. В окружении процесса находится весь корневой объект в JSON. Пробелы и порядок полей JSON несущественны. Каждый вариант входа сохраняет эти связи без применения его плана.",
    "de": "Das Feld release entspricht der verwalteten Erzeugerdatei ohne abschließenden Zeilenumbruch. producer_id ist die dauerhafte Objektidentität des Erzeugers und behält ihren Anfangswert. Das Objekt targets enthält genau die aufgeführten Zielschlüssel. In jedem Eintrag entspricht target seinem Schlüssel; release und producer_id entsprechen den Root-Feldern. Ein Beleg ist dieser Eintrag als JSON. Die Prozessumgebung enthält das gesamte Root-Objekt als JSON. Leerzeichen und JSON-Feldreihenfolge sind unerheblich. Jeder Eingabefall muss diese Beziehungen ohne Anwendung seines Plans bewahren.",
    "es": "El campo release corresponde al archivo gestionado del productor sin el salto de línea final. producer_id es la identidad persistente del objeto productor y conserva su valor inicial. El objeto targets tiene exactamente las claves de destino indicadas. En cada entrada, target coincide con su clave y release y producer_id con los campos raíz. Un recibo es esa entrada como JSON. El entorno del proceso contiene todo el objeto raíz como JSON. Los espacios y el orden de miembros JSON no importan. Cada caso de entrada debe conservar estas relaciones sin aplicar su plan.",
    "pl": "Pole release odpowiada zarządzanemu plikowi producenta bez końcowego znaku nowego wiersza. producer_id jest trwałą tożsamością obiektu producenta i zachowuje wartość początkową. Obiekt targets zawiera dokładnie wymienione klucze odbiorców. W każdym wpisie target jest równy jego kluczowi, a release i producer_id odpowiadają polom głównym. Potwierdzenie to ten wpis jako JSON. Środowisko procesu zawiera cały obiekt główny jako JSON. Odstępy i kolejność pól JSON nie mają znaczenia. Każdy przypadek wejściowy musi zachować te relacje bez zastosowania planu."
  }
}
DQ_SCHEMA
tofu init -input=false -no-color
