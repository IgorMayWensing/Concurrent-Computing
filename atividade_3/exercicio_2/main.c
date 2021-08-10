#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <stdio.h>
#include <pthread.h>

// Lê o conteúdo do arquivo filename e retorna um vetor E o tamanho dele
// Se filename for da forma "gen:%d", gera um vetor aleatório com %d elementos
//
// +-------> retorno da função, ponteiro para vetor malloc()ado e preenchido
// | 
// |         tamanho do vetor (usado <-----+
// |         como 2o retorno)              |
// v                                       v
double* load_vector(const char* filename, int* out_size);


// Avalia o resultado no vetor c. Assume-se que todos os ponteiros (a, b, e c)
// tenham tamanho size.
void avaliar(double* a, double* b, double* c, int size);

typedef struct vetores_t{
    double* a;
    double* b; 
    double* c;
    int start;
    int end;
}vetores;

void* func(void* arg) {
    vetores v = *(vetores*) arg;
    // printf("v->a[0] na func %lf\n", v->a[0]);
    // printf("&v na func %p\n", v);
    for (int i = v.start; i < v.end; i++){
        v.c[i] = v.a[i] + v.b[i];
    }
    pthread_exit(NULL);
}

int main(int argc, char* argv[]) {
    // Gera um resultado diferente a cada execução do programa
    // Se **para fins de teste** quiser gerar sempre o mesmo valor
    // descomente o srand(0)
    srand(time(NULL)); //valores diferentes
    //srand(0);        //sempre mesmo valor

    //Temos argumentos suficientes?
    if(argc < 4) {
        printf("Uso: %s n_threads a_file b_file\n"
               "    n_threads    número de threads a serem usadas na computação\n"
               "    *_file       caminho de arquivo ou uma expressão com a forma gen:N,\n"
               "                 representando um vetor aleatório de tamanho N\n",
               argv[0]);
        return 1;
    }
  
    //Quantas threads?
    int n_threads = atoi(argv[1]);
    if (!n_threads) {
        printf("Número de threads deve ser > 0\n");
        return 1;
    }
    //Lê números de arquivos para vetores alocados com malloc
    int a_size = 0, b_size = 0;
    double* a = load_vector(argv[2], &a_size);
    if (!a) {
        //load_vector não conseguiu abrir o arquivo
        printf("Erro ao ler arquivo %s\n", argv[2]);
        return 1;
    }
    double* b = load_vector(argv[3], &b_size);
    if (!b) {
        printf("Erro ao ler arquivo %s\n", argv[3]);
        return 1;
    }
    //Garante que entradas são compatíveis
    if (a_size != b_size) {
        printf("Vetores a e b tem tamanhos diferentes! (%d != %d)\n", a_size, b_size);
        return 1;
    }

    //Cria vetor do resultado 
    double* c = malloc(a_size*sizeof(double));
   
    vetores v[n_threads];
    

    // printf("a[0] %lf\n", a[0]);
    // printf("a %p\n", a);
    // printf("v->a %lf\n", v->a[0]);
    // printf("&v %p\n", v);
    // printf("&a[0] %p\n", &a[0]);
    // printf("&v->a %p\n", &v->a[0]);

    if (n_threads > a_size) {
        n_threads = a_size;
    }
    pthread_t t[n_threads];

    

    for (int i = 0; i < n_threads; i++) {
        v[i].a = a;
        v[i].b = b;
        v[i].c = c;
        v[i].start = i*(a_size/n_threads);
        v[i].end = v[i].start + (a_size/n_threads) 
                + (i == n_threads-1 ? (a_size - n_threads*(a_size/n_threads)) : 0);
        pthread_create(&t[i], NULL, &func, (void*)&v[i]);
    }    
    for (int i = 0; i < n_threads; i++) {
        pthread_join(t[i], NULL);
    }
    
    // Calcula com uma thread só. Programador original só deixou a leitura 
    // do argumento e fugiu pro caribe. É essa computação que você precisa 
    // paralelizar

    // for (int i = 0; i < a_size; ++i) 
    //     c[i] = a[i] + b[i];

    //    +---------------------------------+
    // ** | IMPORTANTE: avalia o resultado! | **
    //    +---------------------------------+
    avaliar(a, b, c, a_size);
    

    //Importante: libera memória
    free(a);
    free(b);
    free(c);
    return 0;
}
