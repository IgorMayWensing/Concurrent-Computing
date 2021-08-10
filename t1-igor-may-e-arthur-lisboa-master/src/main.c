#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include "types.h"
#include "queue.h"

TicketCaller* pc;
pthread_mutex_t dispensadorDeSenhas, mutexCursor, mutexFila;
sem_t clienteProntoParaSerAtendido, semaforoFila;
client_t* listaClientes;
clerk_t* listaClerks;
struct Queue* filaDePedidos;
order_t* balcaoDePedidosFinalizados;

int get_client_id(int senha) {
	for (int i = 0; i < numClients; i++) {
		if (listaClientes[i].password == senha) {
			return listaClientes[i].id;
		}
	}
}

void client_inform_order(order_t* od, int clerk_id) {
	//Atribuição que garante que o order seja passado do client para o clerk.
	pc->clerks_order_spot[clerk_id] = od;
	
	//Semáforo para indicar ao clerk que o cliente "já informou" o pedido.
	sem_post(&listaClerks[clerk_id].esperaClienteInformar);
}

void client_think_order() {
	sleep(rand() % (clientMaxThinkSec + CLIENT_MIN_THINK_SEC) + CLIENT_MIN_THINK_SEC);
}

void client_wait_order(order_t* od) {
	//Semáforo para garantir que o cliente espere o cooker finalizar o seu pedido.
	sem_wait(&listaClientes[od->client_id].semClient);
}

void clerk_create_order(order_t* od) {
	//Adiciona o pedido na fila para ser cozinhado pelo cooker de forma protegida.
	pthread_mutex_lock(&mutexFila);
	enQueue(filaDePedidos, *od);
	pthread_mutex_unlock(&mutexFila);

	//Indica ao cooker que existe um novo pedido para ser cozinhado.
	sem_post(&semaforoFila);
}

void clerk_annotate_order() {
	sleep(rand() % (clerkMaxWaitSec + CLERK_MIN_WAIT_SEC) + CLERK_MIN_WAIT_SEC);
}

void cooker_wait_cook_time() {
	sleep(rand() % (cookMaxWaitSec + COOK_MIN_WAIT_SEC) + COOK_MIN_WAIT_SEC);
}

void* client(void *args) {
	client_t* cl = (client_t*) args;
	
	//Mutex usado para proteger o acesso à senha.
	pthread_mutex_lock(&dispensadorDeSenhas);
	int pw = get_unique_ticket(pc);
	pthread_mutex_unlock(&dispensadorDeSenhas);
	
	cl->password = pw;

	//Semáforo que indica à um atendente que existe um cliente pronto para ser atendido.
	sem_post(&clienteProntoParaSerAtendido);

	//Semáforo exclusivo de cada cliente, feito para garantir que só o cliente 
	//chamado seja atendido.
	sem_wait(&cl->semClient);
	for (int i = 0; i < numClerks; i++) {
		if (cl->password == pc->current_password[i]) {	
			client_think_order();
			
			order_t pedido;
			pedido.client_id = cl->id;
			pedido.password_num = cl->password;
			
			client_inform_order(&pedido, i);
			client_wait_order(&pedido);
			break;	
		}
	}	
}

void* clerk(void *args) {
	clerk_t* ck = (clerk_t*) args;

	while(1) { 
		
		//Mutex para garantir acesso seguro ao conteúdo da condição do "if" da linha 97.
		pthread_mutex_lock(&mutexCursor);
		if (pc->gen_cursor < numClients) {
			
			//Semáforo que indica ao atendente que existe um cliente pronto para ser atendido.
			sem_wait(&clienteProntoParaSerAtendido);
			
			int pw = get_retrieved_ticket(pc); 
			
			//Libera o mutex da linha 96.
			pthread_mutex_unlock(&mutexCursor); 
			
			set_current_ticket(pc, pw, ck->id);
			int cid = get_client_id(pw);
			
			//Semáforo que chama o cliente da senha "pw" para vir ser atendido por este clerk.
			sem_post(&listaClientes[cid].semClient);
			
			//Semáforo para indicar ao clerk que o cliente "já informou" o pedido.
			sem_wait(&listaClerks[ck->id].esperaClienteInformar);
			
			order_t* pedido = pc->clerks_order_spot[ck->id];
			pedido->clerk_id = ck->id;
			
			clerk_annotate_order();
			anounce_clerk_order(pedido);
			clerk_create_order(pedido);
			
		} else {
			//Libera o mutex da linha 96.
			pthread_mutex_unlock(&mutexCursor); 
			
			break;
		}
	}
}

void* cooker(void *args) {
	int num_plates = 0;
	
	while(num_plates < numClients) {
		
		//Espera existir um pedido para cozinhar.
		sem_wait(&semaforoFila);
		
		order_t pedido = deQueue(filaDePedidos);
		
		cooker_wait_cook_time();
		balcaoDePedidosFinalizados[pedido.client_id] = pedido;
		anounce_cooker_order(&pedido);
		num_plates++;
		
		//Avisa ao cliente que o pedido está pronto.
		sem_post(&listaClientes[pedido.client_id].semClient);
		
	}
}
		
int main(int argc, char *argv[]) {
	parseArgs(argc, argv);
	pc = init_ticket_caller();

	//Declarando as threads.
	pthread_t clients[numClients], clerks[numClerks], cooker1;
	
	//Criando fila de pedidos.
	filaDePedidos = createQueue();
	
	//Mallocs.
	balcaoDePedidosFinalizados = malloc(numClients*sizeof(order_t));
	listaClerks = malloc(numClerks*sizeof(clerk_t));
	listaClientes = malloc(numClients*sizeof(client_t));
	
	//Inicialização dos mutexes.
	pthread_mutex_init(&mutexCursor, NULL);
	pthread_mutex_init(&dispensadorDeSenhas, NULL);
	pthread_mutex_init(&mutexFila, NULL);
	
	//Inicialização dos semáforos.
	sem_init(&clienteProntoParaSerAtendido, 0, 0);
	sem_init(&semaforoFila, 0, 0);
	
	//Criando thread de clientes.
	for (int i = 0; i < numClients; i++) {
		listaClientes[i].id = i;
		sem_init(&listaClientes[i].semClient, 0, 0);
		pthread_create(&clients[i], NULL, client,(void *)&listaClientes[i]);
	}
	
	//Criando thread de atendentes.
	for (int i = 0; i < numClerks; i++) {
		listaClerks[i].id = i;
		sem_init(&listaClerks[i].esperaClienteInformar, 0, 0);
		pthread_create(&clerks[i], NULL, clerk,(void *)&listaClerks[i]);
	}
	
	//Criando thread de cozinheiro.
	pthread_create(&cooker1, NULL, cooker, NULL);
	
	//Joins e Destroys.
	for (int i = 0; i < numClients; i++) {
		pthread_join(clients[i], NULL);
		sem_destroy(&listaClientes[i].semClient);
	}
	for (int i = 0; i < numClerks; i++) {
		pthread_join(clerks[i], NULL);
		sem_destroy(&listaClerks[i].esperaClienteInformar);
	}	
	pthread_join(cooker1, NULL);
	
	//Free.
	free(balcaoDePedidosFinalizados);
	free(listaClerks);
	free(listaClientes);
	free(pc);

	//Destroy.
	pthread_mutex_destroy(&mutexCursor);
	pthread_mutex_destroy(&dispensadorDeSenhas);
	pthread_mutex_destroy(&mutexFila);
	sem_destroy(&clienteProntoParaSerAtendido);
	sem_destroy(&semaforoFila);

	return 0;
}