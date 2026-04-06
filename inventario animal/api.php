<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { exit(0); }

require_once __DIR__ . '/config/database.php';

$module = $_GET['module'] ?? '';
$action = $_GET['action'] ?? '';
$method = $_SERVER['REQUEST_METHOD'];
$input = json_decode(file_get_contents('php://input'), true) ?? [];
$db = getDB();

try {
    switch ($module) {

        // ===================== DASHBOARD =====================
        case 'dashboard':
            $stats = [];
            $stats['total_bovinos'] = $db->query("SELECT COUNT(*) FROM animales WHERE tipo='bovino' AND estado='activo'")->fetchColumn();
            $stats['total_avicolas'] = $db->query("SELECT COUNT(*) FROM animales WHERE tipo='avicola' AND estado='activo'")->fetchColumn();
            $stats['leche_hoy'] = $db->query("SELECT COALESCE(SUM(cantidad_litros),0) FROM produccion_leche WHERE fecha=CURRENT_DATE")->fetchColumn();
            $stats['huevos_hoy'] = $db->query("SELECT COALESCE(SUM(cantidad),0) FROM produccion_huevos WHERE fecha=CURRENT_DATE")->fetchColumn();
            $stats['vacunas_pendientes'] = $db->query("SELECT COUNT(*) FROM vacunaciones WHERE proxima_fecha <= CURRENT_DATE + INTERVAL '7 days' AND proxima_fecha >= CURRENT_DATE")->fetchColumn();
            $stats['animales_enfermos'] = $db->query("SELECT COUNT(*) FROM animales WHERE estado='enfermo'")->fetchColumn();
            $stats['inseminaciones_pendientes'] = $db->query("SELECT COUNT(*) FROM inseminaciones WHERE resultado='pendiente'")->fetchColumn();
            $stats['partos_proximos'] = $db->query("SELECT COUNT(*) FROM inseminaciones WHERE resultado='exitosa' AND fecha_parto_estimada BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'")->fetchColumn();

            // Producción leche últimos 7 días
            $stats['leche_7dias'] = $db->query("
                SELECT fecha, SUM(cantidad_litros) as total 
                FROM produccion_leche 
                WHERE fecha >= CURRENT_DATE - INTERVAL '7 days' 
                GROUP BY fecha ORDER BY fecha
            ")->fetchAll();

            // Producción huevos últimos 7 días
            $stats['huevos_7dias'] = $db->query("
                SELECT fecha, SUM(cantidad) as total, SUM(rotos) as rotos 
                FROM produccion_huevos 
                WHERE fecha >= CURRENT_DATE - INTERVAL '7 days' 
                GROUP BY fecha ORDER BY fecha
            ")->fetchAll();

            // Distribución por categoría
            $stats['por_categoria'] = $db->query("
                SELECT c.nombre, COUNT(a.id) as total 
                FROM animales a JOIN categorias c ON a.categoria_id=c.id 
                WHERE a.estado='activo' GROUP BY c.nombre ORDER BY total DESC
            ")->fetchAll();

            jsonResponse($stats);
            break;

        // ===================== ANIMALES =====================
        case 'animales':
            if ($method === 'GET' && $action === 'list') {
                $tipo = $_GET['tipo'] ?? '';
                $estado = $_GET['estado'] ?? '';
                $buscar = $_GET['buscar'] ?? '';
                $sql = "SELECT a.*, c.nombre as categoria_nombre FROM animales a LEFT JOIN categorias c ON a.categoria_id=c.id WHERE 1=1";
                $params = [];
                if ($tipo) { $sql .= " AND a.tipo=?"; $params[] = $tipo; }
                if ($estado) { $sql .= " AND a.estado=?"; $params[] = $estado; }
                if ($buscar) { $sql .= " AND (a.codigo ILIKE ? OR a.nombre ILIKE ? OR a.raza ILIKE ?)"; $params[] = "%$buscar%"; $params[] = "%$buscar%"; $params[] = "%$buscar%"; }
                $sql .= " ORDER BY a.created_at DESC";
                $stmt = $db->prepare($sql); $stmt->execute($params);
                jsonResponse($stmt->fetchAll());

            } elseif ($method === 'GET' && $action === 'get') {
                $id = (int)$_GET['id'];
                $stmt = $db->prepare("SELECT a.*, c.nombre as categoria_nombre FROM animales a LEFT JOIN categorias c ON a.categoria_id=c.id WHERE a.id=?");
                $stmt->execute([$id]);
                $animal = $stmt->fetch();
                if (!$animal) jsonResponse(['error' => 'No encontrado'], 404);
                // historial peso
                $stmt2 = $db->prepare("SELECT * FROM historial_peso WHERE animal_id=? ORDER BY fecha");
                $stmt2->execute([$id]);
                $animal['historial_peso'] = $stmt2->fetchAll();
                // vacunaciones
                $stmt3 = $db->prepare("SELECT v.*, vc.nombre as vacuna_nombre FROM vacunaciones v JOIN vacunas vc ON v.vacuna_id=vc.id WHERE v.animal_id=? ORDER BY v.fecha_aplicacion DESC");
                $stmt3->execute([$id]);
                $animal['vacunaciones'] = $stmt3->fetchAll();
                // eventos salud
                $stmt4 = $db->prepare("SELECT * FROM eventos_salud WHERE animal_id=? ORDER BY fecha DESC");
                $stmt4->execute([$id]);
                $animal['eventos_salud'] = $stmt4->fetchAll();
                // inseminaciones
                $stmt5 = $db->prepare("SELECT * FROM inseminaciones WHERE animal_id=? ORDER BY fecha DESC");
                $stmt5->execute([$id]);
                $animal['inseminaciones'] = $stmt5->fetchAll();
                jsonResponse($animal);

            } elseif ($method === 'POST' && $action === 'create') {
                $stmt = $db->prepare("INSERT INTO animales (codigo,nombre,categoria_id,tipo,raza,sexo,fecha_nacimiento,peso_actual,estado,madre_id,padre_id,notas) VALUES (?,?,?,?,?,?,?,?,?,?,?,?) RETURNING id");
                $stmt->execute([$input['codigo'],$input['nombre'],$input['categoria_id']??null,$input['tipo'],$input['raza']??null,$input['sexo']??null,$input['fecha_nacimiento']??null,$input['peso_actual']??null,$input['estado']??'activo',$input['madre_id']??null,$input['padre_id']??null,$input['notas']??null]);
                $id = $stmt->fetchColumn();
                if ($input['peso_actual'] ?? null) {
                    $db->prepare("INSERT INTO historial_peso (animal_id,peso,fecha) VALUES (?,?,CURRENT_DATE)")->execute([$id,$input['peso_actual']]);
                }
                jsonResponse(['id' => $id, 'message' => 'Animal registrado']);

            } elseif ($method === 'PUT' && $action === 'update') {
                $id = (int)$input['id'];
                $stmt = $db->prepare("UPDATE animales SET nombre=?,categoria_id=?,raza=?,sexo=?,fecha_nacimiento=?,peso_actual=?,estado=?,notas=?,updated_at=CURRENT_TIMESTAMP WHERE id=?");
                $stmt->execute([$input['nombre'],$input['categoria_id']??null,$input['raza']??null,$input['sexo']??null,$input['fecha_nacimiento']??null,$input['peso_actual']??null,$input['estado']??'activo',$input['notas']??null,$id]);
                jsonResponse(['message' => 'Actualizado']);

            } elseif ($method === 'DELETE' && $action === 'delete') {
                $id = (int)$_GET['id'];
                $db->prepare("DELETE FROM animales WHERE id=?")->execute([$id]);
                jsonResponse(['message' => 'Eliminado']);
            }
            break;

        // ===================== CATEGORÍAS =====================
        case 'categorias':
            if ($method === 'GET') {
                $tipo = $_GET['tipo'] ?? '';
                $sql = "SELECT * FROM categorias";
                $params = [];
                if ($tipo) { $sql .= " WHERE tipo=?"; $params[] = $tipo; }
                $sql .= " ORDER BY nombre";
                $stmt = $db->prepare($sql); $stmt->execute($params);
                jsonResponse($stmt->fetchAll());
            }
            break;

        // ===================== PESO =====================
        case 'peso':
            if ($method === 'POST') {
                $stmt = $db->prepare("INSERT INTO historial_peso (animal_id,peso,fecha,notas) VALUES (?,?,?,?)");
                $stmt->execute([$input['animal_id'],$input['peso'],$input['fecha']??date('Y-m-d'),$input['notas']??null]);
                $db->prepare("UPDATE animales SET peso_actual=?,updated_at=CURRENT_TIMESTAMP WHERE id=?")->execute([$input['peso'],$input['animal_id']]);
                jsonResponse(['message' => 'Peso registrado']);
            }
            break;

        // ===================== VACUNACIÓN =====================
        case 'vacunacion':
            if ($method === 'GET' && $action === 'vacunas') {
                jsonResponse($db->query("SELECT * FROM vacunas ORDER BY nombre")->fetchAll());
            } elseif ($method === 'POST') {
                $proxima = null;
                if ($input['vacuna_id']) {
                    $intervalo = $db->prepare("SELECT intervalo_dias FROM vacunas WHERE id=?");
                    $intervalo->execute([$input['vacuna_id']]);
                    $dias = $intervalo->fetchColumn();
                    if ($dias > 0) $proxima = date('Y-m-d', strtotime("+{$dias} days", strtotime($input['fecha_aplicacion'] ?? date('Y-m-d'))));
                }
                $stmt = $db->prepare("INSERT INTO vacunaciones (animal_id,vacuna_id,fecha_aplicacion,proxima_fecha,dosis,veterinario,notas) VALUES (?,?,?,?,?,?,?)");
                $stmt->execute([$input['animal_id'],$input['vacuna_id'],$input['fecha_aplicacion']??date('Y-m-d'),$proxima,$input['dosis']??null,$input['veterinario']??null,$input['notas']??null]);
                jsonResponse(['message' => 'Vacunación registrada']);
            }
            break;

        // ===================== EVENTOS SALUD =====================
        case 'salud':
            if ($method === 'POST') {
                $stmt = $db->prepare("INSERT INTO eventos_salud (animal_id,tipo,descripcion,fecha,veterinario,costo,estado) VALUES (?,?,?,?,?,?,?)");
                $stmt->execute([$input['animal_id'],$input['tipo'],$input['descripcion'],$input['fecha']??date('Y-m-d'),$input['veterinario']??null,$input['costo']??0,$input['estado']??'activo']);
                if ($input['tipo'] === 'enfermedad') {
                    $db->prepare("UPDATE animales SET estado='enfermo' WHERE id=?")->execute([$input['animal_id']]);
                }
                jsonResponse(['message' => 'Evento registrado']);
            } elseif ($method === 'PUT') {
                $stmt = $db->prepare("UPDATE eventos_salud SET estado=? WHERE id=?");
                $stmt->execute([$input['estado'],$input['id']]);
                if ($input['estado'] === 'resuelto') {
                    $db->prepare("UPDATE animales SET estado='activo' WHERE id=?")->execute([$input['animal_id']]);
                }
                jsonResponse(['message' => 'Actualizado']);
            }
            break;

        // ===================== PRODUCCIÓN LECHE =====================
        case 'leche':
            if ($method === 'GET') {
                $animal_id = $_GET['animal_id'] ?? '';
                $desde = $_GET['desde'] ?? date('Y-m-d', strtotime('-30 days'));
                $hasta = $_GET['hasta'] ?? date('Y-m-d');
                $sql = "SELECT pl.*, a.nombre as animal_nombre, a.codigo FROM produccion_leche pl JOIN animales a ON pl.animal_id=a.id WHERE pl.fecha BETWEEN ? AND ?";
                $params = [$desde, $hasta];
                if ($animal_id) { $sql .= " AND pl.animal_id=?"; $params[] = $animal_id; }
                $sql .= " ORDER BY pl.fecha DESC, a.nombre";
                $stmt = $db->prepare($sql); $stmt->execute($params);
                jsonResponse($stmt->fetchAll());
            } elseif ($method === 'POST') {
                $stmt = $db->prepare("INSERT INTO produccion_leche (animal_id,fecha,cantidad_litros,turno,calidad,notas) VALUES (?,?,?,?,?,?)");
                $stmt->execute([$input['animal_id'],$input['fecha']??date('Y-m-d'),$input['cantidad_litros'],$input['turno']??null,$input['calidad']??'normal',$input['notas']??null]);
                jsonResponse(['message' => 'Producción registrada']);
            }
            break;

        // ===================== PRODUCCIÓN HUEVOS =====================
        case 'huevos':
            if ($method === 'GET') {
                $desde = $_GET['desde'] ?? date('Y-m-d', strtotime('-30 days'));
                $hasta = $_GET['hasta'] ?? date('Y-m-d');
                $stmt = $db->prepare("SELECT ph.*, a.nombre as lote_nombre, a.codigo FROM produccion_huevos ph LEFT JOIN animales a ON ph.lote_id=a.id WHERE ph.fecha BETWEEN ? AND ? ORDER BY ph.fecha DESC");
                $stmt->execute([$desde, $hasta]);
                jsonResponse($stmt->fetchAll());
            } elseif ($method === 'POST') {
                $stmt = $db->prepare("INSERT INTO produccion_huevos (lote_id,fecha,cantidad,rotos,peso_promedio,notas) VALUES (?,?,?,?,?,?)");
                $stmt->execute([$input['lote_id']??null,$input['fecha']??date('Y-m-d'),$input['cantidad'],$input['rotos']??0,$input['peso_promedio']??null,$input['notas']??null]);
                jsonResponse(['message' => 'Producción registrada']);
            }
            break;

        // ===================== INSEMINACIÓN =====================
        case 'inseminacion':
            if ($method === 'GET') {
                $stmt = $db->query("SELECT i.*, a.nombre as animal_nombre, a.codigo FROM inseminaciones i JOIN animales a ON i.animal_id=a.id ORDER BY i.fecha DESC");
                jsonResponse($stmt->fetchAll());
            } elseif ($method === 'POST') {
                $parto = null;
                if ($input['fecha']) $parto = date('Y-m-d', strtotime('+283 days', strtotime($input['fecha'])));
                $stmt = $db->prepare("INSERT INTO inseminaciones (animal_id,fecha,toro_pajilla,tecnico,resultado,fecha_verificacion,fecha_parto_estimada,notas) VALUES (?,?,?,?,?,?,?,?)");
                $stmt->execute([$input['animal_id'],$input['fecha']??date('Y-m-d'),$input['toro_pajilla']??null,$input['tecnico']??null,$input['resultado']??'pendiente',$input['fecha_verificacion']??null,$parto,$input['notas']??null]);
                jsonResponse(['message' => 'Inseminación registrada']);
            } elseif ($method === 'PUT') {
                $stmt = $db->prepare("UPDATE inseminaciones SET resultado=?,fecha_verificacion=?,notas=? WHERE id=?");
                $parto = $input['resultado'] === 'exitosa' ? date('Y-m-d', strtotime('+283 days', strtotime($input['fecha_original'] ?? date('Y-m-d')))) : null;
                $stmt->execute([$input['resultado'],$input['fecha_verificacion']??date('Y-m-d'),$input['notas']??null,$input['id']]);
                if ($parto) $db->prepare("UPDATE inseminaciones SET fecha_parto_estimada=? WHERE id=?")->execute([$parto,$input['id']]);
                jsonResponse(['message' => 'Actualizado']);
            }
            break;

        // ===================== REPORTES =====================
        case 'reportes':
            if ($action === 'produccion_leche_mensual') {
                $stmt = $db->query("SELECT DATE_TRUNC('month',fecha) as mes, SUM(cantidad_litros) as total FROM produccion_leche GROUP BY mes ORDER BY mes DESC LIMIT 12");
                jsonResponse($stmt->fetchAll());
            } elseif ($action === 'produccion_huevos_mensual') {
                $stmt = $db->query("SELECT DATE_TRUNC('month',fecha) as mes, SUM(cantidad) as total, SUM(rotos) as rotos FROM produccion_huevos GROUP BY mes ORDER BY mes DESC LIMIT 12");
                jsonResponse($stmt->fetchAll());
            } elseif ($action === 'vacunas_proximas') {
                $stmt = $db->query("SELECT v.*, vc.nombre as vacuna_nombre, a.nombre as animal_nombre, a.codigo FROM vacunaciones v JOIN vacunas vc ON v.vacuna_id=vc.id JOIN animales a ON v.animal_id=a.id WHERE v.proxima_fecha BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days' ORDER BY v.proxima_fecha");
                jsonResponse($stmt->fetchAll());
            } elseif ($action === 'inventario_general') {
                $stmt = $db->query("SELECT tipo, estado, COUNT(*) as total FROM animales GROUP BY tipo, estado ORDER BY tipo, estado");
                jsonResponse($stmt->fetchAll());
            }
            break;

        default:
            jsonResponse(['error' => 'Módulo no encontrado'], 404);
    }
} catch (Exception $e) {
    jsonResponse(['error' => $e->getMessage()], 500);
}
