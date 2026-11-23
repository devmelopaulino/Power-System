export function apiError(status,detail,fallback='Não foi possível carregar os dados. Tente novamente.') {
 let message
 if(status===401)message='Sua sessão terminou. Entre novamente; seus dados continuam preservados.'
 else if(status===403)message='Você não tem permissão para esta ação. Confira a conta utilizada ou fale com seu treinador.'
 else if(status===404)message='Este registro não está disponível para sua conta. Volte à lista e atualize os dados.'
 else if(status===413)message='Há informações demais neste envio. Reduza o conteúdo e tente novamente.'
 else if(status===429)message='Muitas tentativas em pouco tempo. Aguarde um momento e tente novamente.'
 else if(status>=500)message='O serviço está temporariamente indisponível. Aguarde um momento e tente novamente.'
 else message=typeof detail==='string'&&detail.trim()?detail:fallback
 const error=new Error(message);error.status=status;return error
}
export async function readApiResponse(response,fallback) {
 let result
 try{result=await response.json()}catch{throw apiError(response.status>=400?response.status:502,null,fallback)}
 if(!response.ok)throw apiError(response.status,result?.erro,fallback)
 return result
}
export function errorMessage(error,fallback='Não foi possível concluir a solicitação. Tente novamente.') {
 if(error instanceof TypeError)return 'Não foi possível conectar ao serviço. Verifique sua conexão e tente novamente.'
 if(error instanceof SyntaxError)return 'A resposta do serviço não pôde ser lida. Tente novamente em instantes.'
 return error?.message||fallback
}
